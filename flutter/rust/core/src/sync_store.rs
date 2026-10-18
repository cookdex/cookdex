//! Immutable revision union. Wall clocks never decide sync winners.
use crate::storage;
#[cfg(test)]
use crate::storage::Book;
use rusqlite::{Connection, params};
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};
use sha2::{Digest, Sha256};
use std::collections::{BTreeMap, BTreeSet, VecDeque};
use uuid::Uuid;
pub const VERSION: u32 = 4;
pub const RECIPE_ERROR: &str = "The other device sent a recipe this device can't read. Make sure both devices run the same cookdex version, then try syncing again. No changes were saved.";
pub const SET_ASIDE_ERROR: &str = "Sync is paused because a recipe couldn't be loaded. Restore a backup or discard the set-aside recipes before syncing.";
const LIMIT: usize = 96 * 1024 * 1024;
const RECENT_VERSIONS: usize = 4;
#[derive(Clone, Debug, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct Event {
    pub id: String,
    pub recipe_id: String,
    pub parents: Vec<String>,
    pub kind: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub recipe: Option<Value>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub deleted_at: Option<String>,
    // Only compact ancestry stubs carry this digest; full events derive it.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub recipe_digest: Option<String>,
}
#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Packet {
    pub version: u32,
    pub events: Vec<Event>,
}
fn err(e: impl std::fmt::Display) -> String {
    e.to_string()
}
fn read_events(db: &Connection) -> Result<Vec<Event>, String> {
    let mut stmt = db
        .prepare("SELECT id,recipe_id,body FROM history ORDER BY id")
        .map_err(err)?;
    let rows = stmt
        .query_map([], |r| {
            Ok((
                r.get::<_, String>(0)?,
                r.get::<_, String>(1)?,
                r.get::<_, String>(2)?,
            ))
        })
        .map_err(err)?;
    let events = rows
        .map(|row| {
            let (id, recipe_id, body) = row.map_err(err)?;
            let event: Event = serde_json::from_str(&body).map_err(err)?;
            if event.id != id || event.recipe_id != recipe_id {
                return Err("Stored revision identity mismatch; no data changed".into());
            }
            Ok(event)
        })
        .collect::<Result<Vec<Event>, String>>()?;
    Ok(events)
}
// Preserve damaged historical payload bytes on disk. Once a valid successor
// exists, only their original digest/ancestry is shared, using existing stubs.
fn readable_history(db: &Connection) -> Result<Vec<Event>, String> {
    let mut events = read_events(db)?;
    for e in &mut events {
        if e.recipe
            .as_ref()
            .is_some_and(|r| r["id"] != e.recipe_id || storage::validate_recipe(r).is_err())
        {
            e.recipe_digest = payload_digest(e)?;
            e.recipe = None;
        }
    }
    Ok(events)
}
pub fn export(db: &Connection) -> Result<Packet, String> {
    if !storage::set_aside_ids(db)?.is_empty() {
        return Err(SET_ASIDE_ERROR.into());
    }
    let packet = Packet {
        version: VERSION,
        events: readable_history(db)?,
    };
    validate_packet(&packet)?;
    graph(packet.events.clone())?;
    Ok(packet)
}
// Inventories bind immutable ancestry and payload identity. A compact stub and
// its original full revision deliberately have the same identity digest.
#[derive(Clone, Debug, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct ManifestEntry {
    pub id: String,
    pub digest: String,
    pub full: bool,
}
#[derive(Clone, Debug, Serialize, Deserialize, PartialEq)]
#[serde(deny_unknown_fields)]
pub struct Manifest {
    pub version: u32,
    pub events: Vec<ManifestEntry>,
}
fn valid_digest(d: &str) -> bool {
    d.len() == 64
        && d.bytes()
            .all(|c| c.is_ascii_digit() || (b'a'..=b'f').contains(&c))
}
fn canonical_bytes(value: &Value) -> Result<Vec<u8>, String> {
    fn sort(value: &mut Value) {
        match value {
            Value::Object(map) => {
                map.sort_keys();
                for v in map.values_mut() {
                    sort(v);
                }
            }
            Value::Array(values) => {
                for v in values {
                    sort(v);
                }
            }
            _ => (),
        }
    }
    let mut value = value.clone();
    sort(&mut value);
    serde_json::to_vec(&value).map_err(err)
}
fn payload_digest(e: &Event) -> Result<Option<String>, String> {
    match &e.recipe {
        Some(recipe) => Ok(Some(format!(
            "{:x}",
            Sha256::digest(canonical_bytes(recipe)?)
        ))),
        None => Ok(e.recipe_digest.clone()),
    }
}
fn identity_digest(e: &Event) -> Result<String, String> {
    let identity = json!({"id":e.id,"recipeId":e.recipe_id,"parents":e.parents,
        "kind":e.kind,"deletedAt":e.deleted_at,"recipeDigest":payload_digest(e)?});
    Ok(format!("{:x}", Sha256::digest(canonical_bytes(&identity)?)))
}
pub fn manifest(packet: &Packet) -> Result<Manifest, String> {
    validate_packet(packet)?;
    Ok(Manifest {
        version: VERSION,
        events: packet
            .events
            .iter()
            .map(|e| {
                Ok(ManifestEntry {
                    id: e.id.clone(),
                    digest: identity_digest(e)?,
                    full: e.recipe_digest.is_none(),
                })
            })
            .collect::<Result<_, String>>()?,
    })
}
pub fn delta(packet: &Packet, remote: &Manifest) -> Result<Packet, String> {
    validate_packet(packet)?;
    if remote.version != VERSION {
        return Err(
            "Incompatible sync inventory. Update every device before syncing; no data changed."
                .into(),
        );
    }
    if remote.events.len() > 100000 || serde_json::to_vec(remote).map_err(err)?.len() > LIMIT {
        return Err("Oversized sync inventory".into());
    }
    let mut known = BTreeMap::new();
    for e in &remote.events {
        if e.id.is_empty()
            || e.id.len() > 128
            || !valid_digest(&e.digest)
            || known.insert(&e.id, &e.digest).is_some()
        {
            return Err("Invalid sync inventory".into());
        }
    }
    let mut events = vec![];
    for e in &packet.events {
        if let Some(digest) = known.get(&e.id) {
            if **digest != identity_digest(e)? {
                return Err("Revision identity collision; no data changed".into());
            }
            // A matching stub proves the revision is already known; do not send
            // retired recipe payloads again to a peer that compacted them.
        } else {
            events.push(e.clone());
        }
    }
    Ok(Packet {
        version: VERSION,
        events,
    })
}
fn write_event(db: &Connection, e: &Event) -> Result<(), String> {
    db.execute(
        "UPDATE history SET body=?2 WHERE id=?1",
        params![e.id, serde_json::to_string(e).map_err(err)?],
    )
    .map_err(err)?;
    Ok(())
}
// Run inside the caller's write transaction. The entire DAG stays available for
// indefinitely offline peers; only recipe bodies are retired. Four recent full
// versions per recipe are preferred, plus every conflict/head. If those exceed
// the packet budget, retire the oldest optional bodies until the packet fits.
pub(crate) fn compact(db: &Connection) -> Result<(), String> {
    compact_with_budget(db, LIMIT)
}
fn compact_with_budget(db: &Connection, budget: usize) -> Result<(), String> {
    if !storage::set_aside_ids(db)?.is_empty() {
        return Ok(());
    }
    let events = readable_history(db)?;
    // Validate original full bodies before retirement, while allowing oversized
    // legacy history to become small enough through compaction.
    validate_events(&events)?;
    let (mut map, heads) = graph(events)?;
    let mut degrees: BTreeMap<String, usize> = map
        .iter()
        .map(|(id, e)| (id.clone(), e.parents.len()))
        .collect();
    let mut children: BTreeMap<String, Vec<String>> = BTreeMap::new();
    for e in map.values() {
        for parent in &e.parents {
            children
                .entry(parent.clone())
                .or_default()
                .push(e.id.clone());
        }
    }
    let mut queue: VecDeque<_> = degrees
        .iter()
        .filter(|(_, n)| **n == 0)
        .map(|(id, _)| id.clone())
        .collect();
    let mut depths: BTreeMap<String, usize> = BTreeMap::new();
    while let Some(id) = queue.pop_front() {
        let depth = map[&id]
            .parents
            .iter()
            .map(|p| depths[p])
            .max()
            .unwrap_or(0)
            + 1;
        depths.insert(id.clone(), depth);
        for child in children.get(&id).into_iter().flatten() {
            let degree = degrees.get_mut(child).unwrap();
            *degree -= 1;
            if *degree == 0 {
                queue.push_back(child.clone());
            }
        }
    }
    let protected: BTreeSet<String> = heads.values().flatten().cloned().collect();
    let mut keep = protected.clone();
    let mut by_recipe: BTreeMap<String, Vec<String>> = BTreeMap::new();
    for e in map.values().filter(|e| e.kind != "delete") {
        by_recipe
            .entry(e.recipe_id.clone())
            .or_default()
            .push(e.id.clone());
    }
    for ids in by_recipe.values_mut() {
        ids.sort_by(|a, b| depths[b].cmp(&depths[a]).then_with(|| b.cmp(a)));
        keep.extend(ids.iter().take(RECENT_VERSIONS).cloned());
    }
    // A peer may already have retired optional payloads due to the size budget.
    // Never rehydrate them merely to fill the preferred history allowance.
    let mut changed = BTreeSet::new();
    for e in map.values_mut() {
        if e.recipe.is_some() && !keep.contains(&e.id) {
            e.recipe_digest = payload_digest(e)?;
            e.recipe = None;
            changed.insert(e.id.clone());
        }
    }
    let mut packet = Packet {
        version: VERSION,
        events: map.values().cloned().collect(),
    };
    let mut size = serde_json::to_vec(&packet).map_err(err)?.len();
    if size > budget {
        let mut optional: Vec<String> = map
            .values()
            .filter(|e| e.recipe.is_some() && !protected.contains(&e.id))
            .map(|e| e.id.clone())
            .collect();
        optional.sort_by(|a, b| depths[a].cmp(&depths[b]).then_with(|| a.cmp(b)));
        for id in optional {
            let e = map.get_mut(&id).unwrap();
            let old_len = serde_json::to_vec(e).map_err(err)?.len();
            e.recipe_digest = payload_digest(e)?;
            e.recipe = None;
            size = size - old_len + serde_json::to_vec(e).map_err(err)?.len();
            changed.insert(id);
            if size <= budget {
                break;
            }
        }
        packet.events = map.values().cloned().collect();
    }
    if size > budget {
        return Err("Recipe history capacity exceeded: current recipes, conflict heads and ancestry cannot fit. No data changed; export a backup before further changes.".into());
    }
    validate_packet(&packet).map_err(|error| format!("Recipe history capacity exceeded or invalid: {error}. No data changed; export a backup before further changes."))?;
    for id in changed {
        write_event(db, &map[&id])?;
    }
    Ok(())
}
pub fn validate_packet(p: &Packet) -> Result<(), String> {
    if p.version != VERSION {
        return Err("Incompatible sync history version. Update every device before syncing; no data changed.".into());
    }
    if p.events.len() > 100000 || serde_json::to_vec(p).map_err(err)?.len() > LIMIT {
        return Err("Unsupported or oversized sync history".into());
    }
    validate_events(&p.events)
}
fn validate_events(events: &[Event]) -> Result<(), String> {
    let mut seen = BTreeSet::new();
    for e in events {
        if e.id.is_empty()
            || e.id.len() > 128
            || e.recipe_id.is_empty()
            || e.recipe_id.len() > 128
            || !seen.insert(&e.id)
            || e.parents.len() > 10000
        {
            return Err("Invalid sync identity".into());
        }
        match e.kind.as_str() {
            "put" | "migration" => {
                if e.deleted_at.is_some() {
                    return Err("Invalid sync recipe identity".into());
                }
                match (&e.recipe, &e.recipe_digest) {
                    (Some(r), None) => {
                        if r["id"] != e.recipe_id {
                            return Err("Invalid sync recipe identity".into());
                        }
                        storage::validate_recipe(r).map_err(|_| RECIPE_ERROR.to_string())?;
                    }
                    (None, Some(d)) if valid_digest(d) => (),
                    _ => return Err("Invalid full revision or compact ancestry digest".into()),
                }
            }
            "delete" => {
                if e.recipe.is_some()
                    || e.recipe_digest.is_some()
                    || e.deleted_at
                        .as_ref()
                        .is_none_or(|v| v.is_empty() || v.len() > 128)
                {
                    return Err("Invalid deletion".into());
                }
            }
            _ => return Err("Unknown sync operation".into()),
        }
    }
    Ok(())
}
fn graph(
    events: Vec<Event>,
) -> Result<(BTreeMap<String, Event>, BTreeMap<String, Vec<String>>), String> {
    let map: BTreeMap<_, _> = events.into_iter().map(|e| (e.id.clone(), e)).collect();
    let mut degree = BTreeMap::new();
    let mut children: BTreeMap<String, Vec<String>> = BTreeMap::new();
    let mut heads: BTreeMap<String, BTreeSet<String>> = BTreeMap::new();
    for e in map.values() {
        heads
            .entry(e.recipe_id.clone())
            .or_default()
            .insert(e.id.clone());
    }
    for e in map.values() {
        let mut unique = BTreeSet::new();
        for p in &e.parents {
            if !unique.insert(p)
                || map
                    .get(p)
                    .is_none_or(|parent| parent.recipe_id != e.recipe_id)
            {
                return Err("Missing or invalid revision parent".into());
            }
            children.entry(p.clone()).or_default().push(e.id.clone());
            heads.get_mut(&e.recipe_id).unwrap().remove(p);
        }
        degree.insert(e.id.clone(), e.parents.len());
    }
    let mut queue: VecDeque<_> = degree
        .iter()
        .filter(|(_, n)| **n == 0)
        .map(|(id, _)| id.clone())
        .collect();
    let mut visited = 0;
    while let Some(id) = queue.pop_front() {
        visited += 1;
        for child in children.get(&id).into_iter().flatten() {
            let n = degree.get_mut(child).unwrap();
            *n -= 1;
            if *n == 0 {
                queue.push_back(child.clone())
            }
        }
    }
    if visited != map.len() {
        return Err("Cyclic sync history".into());
    }
    for ids in heads.values() {
        if ids.iter().any(|id| map[id].recipe_digest.is_some()) {
            return Err("Compact ancestry cannot be a recipe head; no data changed".into());
        }
    }
    Ok((
        map,
        heads
            .into_iter()
            .map(|(k, v)| (k, v.into_iter().collect()))
            .collect(),
    ))
}
fn equivalent(a: &Event, b: &Event) -> bool {
    a.recipe == b.recipe && (a.recipe.is_some() || a.kind == b.kind)
}
fn insert(db: &Connection, e: &Event) -> Result<(), String> {
    db.execute(
        "INSERT INTO history VALUES(?1,?2,?3)",
        params![e.id, e.recipe_id, serde_json::to_string(e).map_err(err)?],
    )
    .map_err(err)?;
    Ok(())
}
pub fn conflicts(db: &Connection) -> Result<Value, String> {
    let excluded = storage::set_aside_ids(db)?;
    let mut value = storage::local(db, "syncConflicts")?.unwrap_or(json!([]));
    value
        .as_array_mut()
        .ok_or("Invalid conflict state")?
        .retain(|c| !excluded.iter().any(|id| c["recipeId"] == *id));
    Ok(value)
}
pub fn merge(db: &mut Connection, p: Packet, saved_at: &str) -> Result<(), String> {
    merge_inner(db, p, saved_at, false)
}
fn merge_inner(db: &mut Connection, p: Packet, saved_at: &str, fail: bool) -> Result<(), String> {
    validate_packet(&p)?;
    let tx = db
        .transaction_with_behavior(rusqlite::TransactionBehavior::Immediate)
        .map_err(err)?;
    let old = storage::snapshot(&tx)?;
    let original = export(&tx)?;
    let mut union: BTreeMap<String, Event> = original
        .events
        .into_iter()
        .map(|e| (e.id.clone(), e))
        .collect();
    let mut added = false;
    for e in p.events {
        if let Some(existing) = union.get(&e.id) {
            if identity_digest(existing)? != identity_digest(&e)? {
                return Err("Revision identity collision; no data changed".into());
            }
            if existing.recipe.is_none() && e.recipe.is_some() {
                write_event(&tx, &e)?;
                union.insert(e.id.clone(), e);
            }
        } else {
            insert(&tx, &e)?;
            union.insert(e.id.clone(), e);
            added = true;
        }
    }
    // Validate the complete graph before updating any projection. Transaction rollback
    // also removes inserted records if a parent, payload or limit check fails.
    let (mut map, mut heads) = graph(union.into_values().collect())?;
    for (recipe_id, ids) in heads.iter_mut() {
        if ids.len() > 1 && ids.iter().all(|id| equivalent(&map[id], &map[&ids[0]])) {
            let id = format!(
                "merge-{:x}",
                Sha256::digest(serde_json::to_vec(ids).map_err(err)?)
            );
            let mut e = map[&ids[0]].clone();
            e.id = id.clone();
            e.recipe_id = recipe_id.clone();
            e.parents = ids.clone();
            insert(&tx, &e)?;
            map.insert(id.clone(), e);
            *ids = vec![id];
            added = true;
        }
    }
    compact(&tx)?;
    if !added {
        if fail {
            return Err("Injected sync commit failure".into());
        }
        tx.commit().map_err(err)?;
        return Ok(());
    }
    storage::put_local(
        &tx,
        "previous",
        &json!({"savedAt":saved_at,"book":old.book}),
    )?;
    let mut problems = vec![];
    let mut deletions = vec![];
    for (recipe_id, ids) in heads {
        let chosen = if ids.len() == 1 {
            ids[0].clone()
        } else {
            problems.push(json!({"recipeId":recipe_id,"versions":ids.iter().map(|id|&map[id]).collect::<Vec<_>>()}));
            // Keep the visible local recipe until explicit resolution. If absent, show a
            // surviving recipe version rather than applying a concurrent deletion.
            let local = old.book.recipes.iter().find(|r| r["id"] == recipe_id);
            ids.iter()
                .find(|id| map[*id].recipe.as_ref() == local && local.is_some())
                .or_else(|| ids.iter().find(|id| map[*id].recipe.is_some()))
                .unwrap_or(&ids[0])
                .clone()
        };
        let e = &map[&chosen];
        tx.execute("INSERT INTO heads VALUES(?1,?2) ON CONFLICT(recipe_id) DO UPDATE SET revision_id=excluded.revision_id",params![recipe_id,chosen]).map_err(err)?;
        if let Some(recipe) = &e.recipe {
            tx.execute("INSERT INTO recipes VALUES(?1,?2,?3) ON CONFLICT(id) DO UPDATE SET body=excluded.body,revision_id=excluded.revision_id",params![recipe_id,recipe.to_string(),chosen]).map_err(err)?;
        } else {
            tx.execute("DELETE FROM recipes WHERE id=?1", [&recipe_id])
                .map_err(err)?;
            deletions.push(json!({"id":recipe_id,"deletedAt":e.deleted_at}));
        }
    }
    storage::put_local(&tx, "deletedRecipes", &json!(deletions))?;
    storage::put_local(&tx, "syncConflicts", &json!(problems))?;
    tx.execute("UPDATE state SET generation=generation+1 WHERE id=1", [])
        .map_err(err)?;
    storage::snapshot(&tx)?;
    if fail {
        return Err("Injected sync commit failure".into());
    }
    tx.commit().map_err(err)?;
    Ok(())
}
pub fn resolve(
    db: &mut Connection,
    recipe_id: &str,
    expected: &[String],
    choice: &str,
    saved_at: &str,
) -> Result<(), String> {
    let p = export(db)?;
    let (map, heads) = graph(p.events)?;
    let ids = heads.get(recipe_id).ok_or("Conflict no longer exists")?;
    let mut expected = expected.to_vec();
    expected.sort();
    if ids.len() < 2 || *ids != expected {
        return Err("Conflict changed. Refresh and review the new versions.".into());
    }
    let chosen = if choice == "keep-all" {
        ids.iter()
            .find(|id| map[*id].recipe.is_some())
            .ok_or("No recipe versions to keep")?
    } else {
        ids.iter()
            .find(|id| id.as_str() == choice)
            .ok_or("Unknown version")?
    };
    let mut e = map[chosen].clone();
    e.id = Uuid::new_v4().to_string();
    e.parents = ids.clone();
    let mut events = vec![e];
    if choice == "keep-all" {
        let mut copies = vec![map[chosen].recipe.clone()];
        for id in ids {
            let version = &map[id];
            if version.recipe.is_some() && !copies.contains(&version.recipe) {
                copies.push(version.recipe.clone());
                let mut copy = version.clone();
                copy.id = Uuid::new_v4().to_string();
                copy.recipe_id = Uuid::new_v4().to_string();
                copy.parents.clear();
                copy.recipe.as_mut().unwrap()["id"] = json!(copy.recipe_id);
                events.push(copy);
            }
        }
    }
    merge(
        db,
        Packet {
            version: VERSION,
            events,
        },
        saved_at,
    )
}
#[cfg(test)]
mod tests {
    use super::*;
    fn db() -> Connection {
        storage::open(std::path::Path::new(":memory:")).unwrap()
    }
    fn fixture() -> Book {
        serde_json::from_str(include_str!("../tests/native-fixture.json")).unwrap()
    }
    fn push(a: &Connection, b: &mut Connection) {
        merge(b, export(a).unwrap(), "sync").unwrap()
    }
    #[test]
    fn three_devices_offline_conflict_resolution_deletion_and_idempotency() {
        let (mut a, mut b, mut c) = (db(), db(), db());
        let initial = fixture();
        storage::save(&mut a, 0, &initial, "a").unwrap();
        push(&a, &mut b);
        push(&b, &mut c);
        let mut ab = storage::load(&mut a).unwrap();
        ab.book.recipes[0]["notes"] = json!("A offline");
        storage::save(&mut a, ab.generation, &ab.book, "a2").unwrap();
        let mut bb = storage::load(&mut b).unwrap();
        bb.book.recipes[0]["notes"] = json!("B offline");
        bb.book.shopping = initial.shopping.clone();
        storage::save(&mut b, bb.generation, &bb.book, "b2").unwrap();
        push(&a, &mut b);
        assert_eq!(conflicts(&b).unwrap().as_array().unwrap().len(), 1);
        push(&b, &mut c);
        let problem = conflicts(&c).unwrap()[0].clone();
        let ids: Vec<String> = problem["versions"]
            .as_array()
            .unwrap()
            .iter()
            .map(|e| e["id"].as_str().unwrap().to_string())
            .collect();
        resolve(
            &mut c,
            problem["recipeId"].as_str().unwrap(),
            &ids,
            "keep-all",
            "resolve",
        )
        .unwrap();
        push(&c, &mut b);
        push(&b, &mut a);
        assert_eq!(conflicts(&a).unwrap(), json!([]));
        assert_eq!(
            storage::load(&mut a).unwrap().book.recipes.len(),
            initial.recipes.len() + 1
        );
        assert_eq!(
            storage::load(&mut b).unwrap().book.shopping,
            initial.shopping
        );
        let before = storage::load(&mut a).unwrap().generation;
        push(&b, &mut a);
        assert_eq!(storage::load(&mut a).unwrap().generation, before);
        let mut next = storage::load(&mut a).unwrap();
        let removed = next.book.recipes.remove(0);
        storage::save(&mut a, next.generation, &next.book, "deleted").unwrap();
        push(&a, &mut c);
        assert!(
            !storage::load(&mut c)
                .unwrap()
                .book
                .recipes
                .contains(&removed)
        );
        push(&b, &mut c);
        assert!(
            !storage::load(&mut c)
                .unwrap()
                .book
                .recipes
                .contains(&removed)
        );
    }
    #[test]
    fn identical_independent_backups_merge_without_conflict() {
        let (mut a, mut b) = (db(), db());
        storage::save(&mut a, 0, &fixture(), "a").unwrap();
        storage::save(&mut b, 0, &fixture(), "b").unwrap();
        push(&a, &mut b);
        push(&b, &mut a);
        assert_eq!(conflicts(&a).unwrap(), json!([]));
        assert_eq!(export(&a).unwrap().events, export(&b).unwrap().events);
    }
    #[test]
    fn previous_save_recovery_supersedes_synced_deletion_on_every_device() {
        // Both the deleting device and a peer can recover through the normal save
        // path. Replaying deletion-era history must never delete that recovery.
        for recover_on_peer in [false, true] {
            let (mut a, mut b, mut c) = (db(), db(), db());
            let initial = fixture();
            let recipe_id = initial.recipes[0]["id"].as_str().unwrap();
            storage::save(&mut a, 0, &initial, "initial").unwrap();
            push(&a, &mut b);
            push(&a, &mut c);
            let initial_packet = export(&a).unwrap();

            let mut deleted = storage::load(&mut a).unwrap();
            deleted.book.recipes.remove(0);
            deleted.book.deleted_recipes = vec![json!({
                "id": recipe_id, "deletedAt": "deleted"
            })];
            storage::save(&mut a, deleted.generation, &deleted.book, "deleted").unwrap();
            let deletion_packet = export(&a).unwrap();
            let deletion = deletion_packet
                .events
                .iter()
                .find(|e| e.recipe_id == recipe_id && e.kind == "delete")
                .unwrap();
            push(&a, &mut b);
            push(&b, &mut c);
            for device in [&mut a, &mut b, &mut c] {
                assert!(storage::load(device).unwrap().book.recipes.is_empty());
            }

            let recovering = if recover_on_peer { &mut b } else { &mut a };
            let previous = storage::previous(recovering).unwrap().unwrap();
            let recovered: Book = serde_json::from_value(previous["book"].clone()).unwrap();
            assert_eq!(recovered, initial);
            let current = storage::load(recovering).unwrap();
            storage::save(recovering, current.generation, &recovered, "recover").unwrap();
            let recovered_packet = export(recovering).unwrap();
            let (_, heads) = graph(recovered_packet.events.clone()).unwrap();
            let recovery = recovered_packet
                .events
                .iter()
                .find(|e| e.id == heads[recipe_id][0])
                .unwrap();
            assert_eq!(heads[recipe_id].len(), 1);
            assert_eq!(recovery.kind, "put");
            assert_eq!(recovery.recipe.as_ref(), Some(&initial.recipes[0]));
            assert_eq!(recovery.parents, vec![deletion.id.clone()]);

            // Deliver recovery to the third device first, then back around the
            // ring, exercising peers that all already applied the deletion.
            merge(&mut c, recovered_packet, "recovered-sync").unwrap();
            push(&c, &mut a);
            push(&a, &mut b);
            let converged = export(&a).unwrap().events;
            for device in [&mut a, &mut b, &mut c] {
                let generation = storage::load(device).unwrap().generation;
                merge(device, deletion_packet.clone(), "old-deletion").unwrap();
                merge(device, initial_packet.clone(), "old-initial").unwrap();
                let stored = storage::load(device).unwrap();
                assert_eq!(stored.book, initial);
                assert_eq!(stored.generation, generation);
                assert_eq!(conflicts(device).unwrap(), json!([]));
                assert_eq!(export(device).unwrap().events, converged);
            }
            push(&b, &mut a);
            push(&a, &mut c);
            assert_eq!(storage::load(&mut c).unwrap().book, initial);
        }
    }
    #[test]
    fn recipe_backup_requires_resolution_and_reads_current_snapshot_without_writing() {
        for delete_on_peer in [false, true] {
            let (mut a, mut b) = (db(), db());
            storage::save(&mut a, 0, &fixture(), "initial").unwrap();
            push(&a, &mut b);
            let mut left = storage::load(&mut a).unwrap();
            left.book.recipes[0]["notes"] = json!("A offline");
            storage::save(&mut a, left.generation, &left.book, "edit-a").unwrap();
            let mut right = storage::load(&mut b).unwrap();
            if delete_on_peer {
                right.book.recipes.remove(0);
            } else {
                right.book.recipes[0]["notes"] = json!("B offline");
            }
            storage::save(&mut b, right.generation, &right.book, "change-b").unwrap();
            push(&a, &mut b);

            let problems = conflicts(&b).unwrap();
            assert_eq!(problems.as_array().unwrap().len(), 1);
            let before = storage::load(&mut b).unwrap();
            let history = export(&b).unwrap().events;
            let previous = storage::previous(&b).unwrap();
            let error = storage::backup_recipes(&mut b).unwrap_err();
            assert!(error.contains("Resolve sync conflicts"));
            let after = storage::load(&mut b).unwrap();
            assert_eq!(after.generation, before.generation);
            assert_eq!(after.book, before.book);
            assert_eq!(export(&b).unwrap().events, history);
            assert_eq!(storage::previous(&b).unwrap(), previous);
            assert_eq!(conflicts(&b).unwrap(), problems);

            let problem = &problems[0];
            let ids: Vec<String> = problem["versions"]
                .as_array()
                .unwrap()
                .iter()
                .map(|e| e["id"].as_str().unwrap().to_string())
                .collect();
            resolve(
                &mut b,
                problem["recipeId"].as_str().unwrap(),
                &ids,
                "keep-all",
                "resolve",
            )
            .unwrap();
            let resolved = storage::load(&mut b).unwrap();
            assert_eq!(conflicts(&b).unwrap(), json!([]));
            let history = export(&b).unwrap().events;
            let previous = storage::previous(&b).unwrap();
            let recipes = storage::backup_recipes(&mut b).unwrap();
            assert_eq!(recipes, resolved.book.recipes);
            assert_eq!(recipes.len(), if delete_on_peer { 1 } else { 2 });
            assert!(recipes.iter().any(|r| r["notes"] == "A offline"));
            if !delete_on_peer {
                assert!(recipes.iter().any(|r| r["notes"] == "B offline"));
            }
            let after = storage::load(&mut b).unwrap();
            assert_eq!(after.generation, resolved.generation);
            assert_eq!(after.book, resolved.book);
            assert_eq!(export(&b).unwrap().events, history);
            assert_eq!(storage::previous(&b).unwrap(), previous);
        }
    }
    #[test]
    fn recipe_backup_fails_closed_on_malformed_conflict_state() {
        let mut a = db();
        storage::save(&mut a, 0, &fixture(), "initial").unwrap();
        let before = storage::load(&mut a).unwrap();
        let history = export(&a).unwrap().events;
        let previous = storage::previous(&a).unwrap();
        storage::put_local(&a, "syncConflicts", &json!({"invalid": true})).unwrap();
        assert!(
            storage::backup_recipes(&mut a)
                .unwrap_err()
                .contains("Invalid conflict state")
        );
        assert_eq!(
            storage::local(&a, "syncConflicts").unwrap(),
            Some(json!({"invalid":true}))
        );
        storage::put_local(&a, "syncConflicts", &json!([])).unwrap();
        let after = storage::load(&mut a).unwrap();
        assert_eq!(after.generation, before.generation);
        assert_eq!(after.book, before.book);
        assert_eq!(export(&a).unwrap().events, history);
        assert_eq!(storage::previous(&a).unwrap(), previous);
    }
    #[test]
    fn invalid_and_interrupted_sync_is_atomic() {
        let (mut a, mut b) = (db(), db());
        storage::save(&mut a, 0, &fixture(), "a").unwrap();
        let mut p = export(&a).unwrap();
        p.events[0].parents = vec!["missing".into()];
        assert!(merge(&mut b, p, "bad").is_err());
        assert!(export(&b).unwrap().events.is_empty());
        assert!(merge_inner(&mut b, export(&a).unwrap(), "fail", true).is_err());
        assert_eq!(storage::load(&mut b).unwrap().generation, 0);
    }
    #[test]
    fn delete_edit_conflict_and_stale_resolution() {
        let (mut a, mut b) = (db(), db());
        storage::save(&mut a, 0, &fixture(), "a").unwrap();
        push(&a, &mut b);
        let mut left = storage::load(&mut a).unwrap();
        left.book.recipes[0]["title"] = json!("Edited");
        storage::save(&mut a, left.generation, &left.book, "edit").unwrap();
        let mut right = storage::load(&mut b).unwrap();
        right.book.recipes.remove(0);
        storage::save(&mut b, right.generation, &right.book, "delete").unwrap();
        push(&a, &mut b);
        assert_eq!(conflicts(&b).unwrap().as_array().unwrap().len(), 1);
        assert!(
            storage::load(&mut b)
                .unwrap()
                .book
                .recipes
                .iter()
                .any(|r| r["title"] == "Edited")
        );
        assert!(resolve(&mut b, "bad", &[], "keep-all", "x").is_err());
    }
}

#[cfg(test)]
mod safety_tests {
    use super::*;
    fn db() -> Connection {
        storage::open(std::path::Path::new(":memory:")).unwrap()
    }
    fn fixture() -> Book {
        serde_json::from_str(include_str!("../tests/native-fixture.json")).unwrap()
    }
    #[test]
    fn stale_edit_after_sync_and_conflicted_recipe_blocked() {
        let (mut a, mut b) = (db(), db());
        storage::save(&mut a, 0, &fixture(), "a").unwrap();
        merge(&mut b, export(&a).unwrap(), "sync").unwrap();
        let stale = storage::load(&mut b).unwrap();
        let mut a_edit = storage::load(&mut a).unwrap();
        a_edit.book.recipes[0]["notes"] = json!("new");
        storage::save(&mut a, a_edit.generation, &a_edit.book, "a2").unwrap();
        merge(&mut b, export(&a).unwrap(), "sync").unwrap();
        assert!(
            storage::save(&mut b, stale.generation, &stale.book, "stale")
                .unwrap_err()
                .contains("STALE_WRITE")
        );
        let mut b_edit = storage::load(&mut b).unwrap();
        b_edit.book.recipes[0]["notes"] = json!("b offline");
        storage::save(&mut b, b_edit.generation, &b_edit.book, "b2").unwrap();
        a_edit = storage::load(&mut a).unwrap();
        a_edit.book.recipes[0]["notes"] = json!("a offline");
        storage::save(&mut a, a_edit.generation, &a_edit.book, "a3").unwrap();
        merge(&mut b, export(&a).unwrap(), "sync").unwrap();
        let mut blocked = storage::load(&mut b).unwrap();
        blocked.book.recipes[0]["title"] = json!("accidental overwrite");
        assert!(
            storage::save(&mut b, blocked.generation, &blocked.book, "x")
                .unwrap_err()
                .contains("sync conflict")
        );
    }
    #[test]
    fn collisions_cycles_and_wrong_recipe_parents_fail_closed() {
        let (mut a, mut b) = (db(), db());
        storage::save(&mut a, 0, &fixture(), "a").unwrap();
        let p = export(&a).unwrap();
        merge(&mut b, p.clone(), "sync").unwrap();
        let before = storage::load(&mut b).unwrap().generation;
        let mut collision = p.clone();
        collision.events[0].recipe.as_mut().unwrap()["title"] = json!("forged");
        assert!(merge(&mut b, collision, "bad").is_err());
        let mut cycle = p.clone();
        cycle.events[0].parents = vec![cycle.events[0].id.clone()];
        let mut c = db();
        assert!(merge(&mut c, cycle, "bad").is_err());
        let mut cross = p.events[0].clone();
        cross.id = "new-cross".into();
        cross.recipe_id = "other-recipe".into();
        cross.recipe.as_mut().unwrap()["id"] = json!("other-recipe");
        cross.parents = vec![p.events[0].id.clone()];
        assert!(
            merge(
                &mut b,
                Packet {
                    version: VERSION,
                    events: vec![cross]
                },
                "bad"
            )
            .is_err()
        );
        assert_eq!(storage::load(&mut b).unwrap().generation, before);
    }
}

#[cfg(test)]
mod persistence_tests {
    use super::*;
    #[test]
    fn shopping_is_never_transferred_and_sync_survives_reopen() {
        let path = std::env::temp_dir().join(format!("recipe-sync-{}.sqlite3", Uuid::new_v4()));
        let mut a = storage::open(std::path::Path::new(":memory:")).unwrap();
        let mut b = storage::open(&path).unwrap();
        let mut first: Book =
            serde_json::from_str(include_str!("../tests/native-fixture.json")).unwrap();
        first.shopping =
            vec![json!({"id":"a-shopping","text":"Only on A","checked":false,"recipeTitle":""})];
        storage::save(&mut a, 0, &first, "first").unwrap();
        let local = Book {
            shopping: vec![
                json!({"id":"b-shopping","text":"Only on B","checked":true,"recipeTitle":""}),
            ],
            ..Book::default()
        };
        storage::save(&mut b, 0, &local, "local").unwrap();
        merge(&mut b, export(&a).unwrap(), "sync").unwrap();
        drop(b);
        let mut b = storage::open(&path).unwrap();
        let reloaded = storage::load(&mut b).unwrap();
        assert_eq!(reloaded.book.shopping, local.shopping);
        assert_eq!(reloaded.book.recipes, first.recipes);
        merge(&mut a, export(&b).unwrap(), "back").unwrap();
        assert_eq!(storage::load(&mut a).unwrap().book.shopping, first.shopping);
        drop(b);
        std::fs::remove_file(path).unwrap();
    }
}

#[cfg(test)]
mod bounded_history_tests {
    use super::*;
    fn db() -> Connection {
        storage::open(std::path::Path::new(":memory:")).unwrap()
    }
    fn fixture() -> Book {
        serde_json::from_str(include_str!("../tests/native-fixture.json")).unwrap()
    }
    fn edit(db: &mut Connection, notes: &str) {
        let mut snapshot = storage::load(db).unwrap();
        snapshot.book.recipes[0]["notes"] = json!(notes);
        storage::save(db, snapshot.generation, &snapshot.book, notes).unwrap();
    }
    fn push(a: &Connection, b: &mut Connection) {
        let source = export(a).unwrap();
        let remote = manifest(&export(b).unwrap()).unwrap();
        merge(b, delta(&source, &remote).unwrap(), "incremental").unwrap();
    }
    #[test]
    fn bounded_payloads_incremental_noop_and_stale_offline_three_device_conflicts() {
        let (mut a, mut b, mut c) = (db(), db(), db());
        storage::save(&mut a, 0, &fixture(), "initial").unwrap();
        let old = export(&a).unwrap();
        push(&a, &mut b);
        push(&a, &mut c);
        for n in 0..24 {
            edit(&mut a, &format!("long edit {n} {}", "x".repeat(8000)));
        }
        let p = export(&a).unwrap();
        assert_eq!(p.events.len(), 25);
        assert_eq!(p.events.iter().filter(|e| e.recipe.is_some()).count(), 4);
        assert_eq!(
            p.events
                .iter()
                .filter(|e| e.recipe_digest.is_some())
                .count(),
            21
        );
        let full_old_digest = manifest(&old).unwrap().events[0].digest.clone();
        assert_eq!(
            manifest(&p)
                .unwrap()
                .events
                .iter()
                .find(|e| e.id == old.events[0].id)
                .unwrap()
                .digest,
            full_old_digest
        );
        // Both peers have been offline since the ancestry that is now compacted.
        edit(&mut b, "B old offline edit");
        let mut deleted = storage::load(&mut c).unwrap();
        deleted.book.recipes.clear();
        storage::save(
            &mut c,
            deleted.generation,
            &deleted.book,
            "C old offline delete",
        )
        .unwrap();
        push(&b, &mut a);
        push(&c, &mut a);
        let problem = conflicts(&a).unwrap()[0].clone();
        assert_eq!(problem["versions"].as_array().unwrap().len(), 3);
        assert!(
            problem["versions"]
                .as_array()
                .unwrap()
                .iter()
                .all(|v| v["recipeDigest"].is_null())
        );
        push(&a, &mut b);
        push(&b, &mut c);
        push(&c, &mut a);
        assert_eq!(export(&a).unwrap().events, export(&b).unwrap().events);
        assert_eq!(export(&b).unwrap().events, export(&c).unwrap().events);
        assert!(
            delta(
                &export(&a).unwrap(),
                &manifest(&export(&b).unwrap()).unwrap()
            )
            .unwrap()
            .events
            .is_empty()
        );
        let generation = storage::load(&mut a).unwrap().generation;
        let previous = storage::previous(&a).unwrap();
        merge(&mut a, old, "stale replay").unwrap();
        assert_eq!(storage::load(&mut a).unwrap().generation, generation);
        assert_eq!(storage::previous(&a).unwrap(), previous);
        assert_eq!(
            export(&a)
                .unwrap()
                .events
                .iter()
                .filter(|e| e.recipe.is_some())
                .count(),
            5
        );
        let ids: Vec<String> = problem["versions"]
            .as_array()
            .unwrap()
            .iter()
            .map(|e| e["id"].as_str().unwrap().into())
            .collect();
        resolve(
            &mut a,
            problem["recipeId"].as_str().unwrap(),
            &ids,
            "keep-all",
            "resolve",
        )
        .unwrap();
        push(&a, &mut c);
        push(&c, &mut b);
        assert_eq!(conflicts(&b).unwrap(), json!([]));
        assert_eq!(storage::load(&mut b).unwrap().book.recipes.len(), 2);
    }
    #[test]
    fn compacted_delete_recovery_and_old_packets_never_resurrect() {
        let (mut a, mut b) = (db(), db());
        storage::save(&mut a, 0, &fixture(), "first").unwrap();
        let old = export(&a).unwrap();
        for n in 0..10 {
            edit(&mut a, &format!("{n}"));
        }
        let latest = storage::load(&mut a).unwrap();
        storage::save(&mut a, latest.generation, &Book::default(), "delete").unwrap();
        let deletion = export(&a).unwrap();
        push(&a, &mut b);
        merge(&mut b, old.clone(), "old put").unwrap();
        assert!(storage::load(&mut b).unwrap().book.recipes.is_empty());
        storage::save(&mut a, latest.generation + 1, &latest.book, "recovery").unwrap();
        push(&a, &mut b);
        merge(&mut b, deletion, "old delete").unwrap();
        merge(&mut b, old, "old put").unwrap();
        assert_eq!(storage::load(&mut b).unwrap().book, latest.book);
        assert_eq!(conflicts(&b).unwrap(), json!([]));
    }
    #[test]
    fn legacy_packets_stub_heads_and_ancestry_collisions_roll_back() {
        let (mut a, mut b) = (db(), db());
        storage::save(&mut a, 0, &fixture(), "first").unwrap();
        let initial = export(&a).unwrap();
        let mut legacy = initial.clone();
        legacy.version = 1;
        assert!(
            merge(&mut b, legacy, "legacy")
                .unwrap_err()
                .contains("Update every device")
        );
        assert!(export(&b).unwrap().events.is_empty());
        let mut stub_head = initial.clone();
        stub_head.events[0].recipe_digest = payload_digest(&stub_head.events[0]).unwrap();
        stub_head.events[0].recipe = None;
        assert!(
            merge(&mut b, stub_head, "bad stub")
                .unwrap_err()
                .contains("cannot be a recipe head")
        );
        push(&a, &mut b);
        for n in 0..5 {
            edit(&mut a, &format!("edit{n}"));
        }
        push(&a, &mut b);
        let before = export(&b).unwrap().events;
        let previous = storage::previous(&b).unwrap();
        let mut collision = initial.clone();
        collision.events[0].recipe.as_mut().unwrap()["notes"] = json!("forged retired payload");
        assert!(
            merge(&mut b, collision, "forged")
                .unwrap_err()
                .contains("collision")
        );
        let mut manifest_collision = manifest(&initial).unwrap();
        manifest_collision.events[0].digest = "0".repeat(64);
        assert!(
            delta(&export(&b).unwrap(), &manifest_collision)
                .unwrap_err()
                .contains("collision")
        );
        let mut ancestry = initial;
        ancestry.events[0].parents = vec!["altered".into()];
        assert!(
            merge(&mut b, ancestry, "forged parent")
                .unwrap_err()
                .contains("collision")
        );
        assert_eq!(export(&b).unwrap().events, before);
        assert_eq!(storage::previous(&b).unwrap(), previous);
        // Fault after inserts, rehydration and compaction must restore all bodies.
        let mut fork = export(&a).unwrap();
        let mut event = fork.events.last().unwrap().clone();
        event.id = "fault-new-head".into();
        event.parents = vec![
            export(&a)
                .unwrap()
                .events
                .iter()
                .find(|e| e.recipe.as_ref().is_some_and(|r| r["notes"] == "edit4"))
                .unwrap()
                .id
                .clone(),
        ];
        event.recipe_digest = None;
        event.recipe = Some(fixture().recipes[0].clone());
        fork.events = vec![event];
        assert!(merge_inner(&mut b, fork, "fault", true).is_err());
        assert_eq!(export(&b).unwrap().events, before);
        assert_eq!(storage::previous(&b).unwrap(), previous);
    }
    #[test]
    fn size_budget_retires_optional_bodies_and_preserves_every_head() {
        let mut a = db();
        storage::save(&mut a, 0, &fixture(), "first").unwrap();
        for n in 0..6 {
            edit(&mut a, &format!("{n}{}", "x".repeat(10000)));
        }
        let original = export(&a).unwrap();
        let (_, heads) = graph(original.events.clone()).unwrap();
        let head = &heads.values().next().unwrap()[0];
        let tx = a.transaction().unwrap();
        compact_with_budget(&tx, 15000).unwrap();
        let compacted = export(&tx).unwrap();
        assert_eq!(
            compacted
                .events
                .iter()
                .filter(|e| e.recipe.is_some())
                .count(),
            1
        );
        assert!(
            compacted
                .events
                .iter()
                .find(|e| &e.id == head)
                .unwrap()
                .recipe
                .is_some()
        );
        assert!(
            compact_with_budget(&tx, 100)
                .unwrap_err()
                .contains("capacity exceeded")
        );
        drop(tx);
        assert_eq!(export(&a).unwrap().events, original.events);
    }
}
