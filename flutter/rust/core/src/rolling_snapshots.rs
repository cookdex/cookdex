//! Device-local, best-effort ZIP snapshots. Callers hold the session database lock.
//! ZIP contents use the public exporter; bookkeeping never enters an archive.
use crate::{backup, recipe::Recipe, storage};
use chrono::{DateTime, Datelike, Local, NaiveDate, Utc};
use rusqlite::Connection;
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use std::{collections::HashSet, fs, io::Write, path::PathBuf};

pub const SIZE_CAP: u64 = 256 * 1024 * 1024;
const HEALTH: &str = "rollingSnapshotHealth";

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct Entry {
    pub id: String,
    pub created_at: String,
    pub day: String,
    pub recipe_count: u32,
    pub omitted_count: u32,
    pub reason: String,
    pub bytes: u64,
    pub fingerprint: String,
}

fn directory(db: &Connection) -> Result<PathBuf, String> {
    let path = db
        .path()
        .filter(|p| !p.is_empty())
        .ok_or("No private snapshot directory")?;
    Ok(PathBuf::from(path)
        .parent()
        .ok_or("No private directory")?
        .join("snapshots"))
}
fn err(e: impl std::fmt::Display) -> String {
    e.to_string()
}

pub fn list(db: &Connection) -> Result<Vec<Entry>, String> {
    let root = directory(db)?;
    if !root.exists() {
        return Ok(vec![]);
    }
    let mut entries = vec![];
    for item in fs::read_dir(&root).map_err(err)? {
        let item = item.map_err(err)?;
        let id = item.file_name().to_string_lossy().into_owned();
        if uuid::Uuid::parse_str(&id).is_err() || !item.file_type().map_err(err)?.is_dir() {
            continue;
        }
        let entry: Entry =
            serde_json::from_slice(&fs::read(item.path().join("info.json")).map_err(err)?)
                .map_err(err)?;
        if entry.id != id
            || entry.day.parse::<NaiveDate>().is_err()
            || DateTime::parse_from_rfc3339(&entry.created_at).is_err()
        {
            return Err("Invalid snapshot metadata".into());
        }
        if fs::metadata(item.path().join("snapshot.zip"))
            .map_err(err)?
            .len()
            != entry.bytes
        {
            return Err("Incomplete snapshot".into());
        }
        entries.push(entry);
    }
    entries.sort_by(|a, b| a.created_at.cmp(&b.created_at).then(a.id.cmp(&b.id)));
    Ok(entries)
}
pub fn read(db: &Connection, id: &str) -> Result<Vec<u8>, String> {
    if uuid::Uuid::parse_str(id).is_err() {
        return Err("Unknown snapshot".into());
    }
    let entry = list(db)?
        .into_iter()
        .find(|e| e.id == id)
        .ok_or("Snapshot no longer available")?;
    if entry.bytes > backup::MAX_ZIP_BYTES as u64 {
        return Err("Snapshot exceeds limit".into());
    }
    let bytes = fs::read(directory(db)?.join(id).join("snapshot.zip")).map_err(err)?;
    backup::read_with_setup(&bytes).map_err(err)?;
    Ok(bytes)
}
pub fn repeatedly_failing(db: &Connection) -> bool {
    storage::local(db, HEALTH)
        .ok()
        .flatten()
        .is_some_and(|v| v["failures"].as_u64().unwrap_or(0) >= 3)
}
pub fn before_sync(db: &mut Connection, pairing: &str) {
    let key = format!("snapshotBeforeSync:{pairing}");
    if storage::local(db, &key).ok().flatten().is_some() {
        return;
    }
    if attempt(db, "before_first_sync") {
        let _ = storage::put_local(db, &key, &serde_json::json!(true));
    }
}

/// Automatic attempts are throttled after failure; risky operations still try immediately.
/// Errors are recorded quietly and never returned to a save or sync caller.
pub fn attempt(db: &mut Connection, reason: &str) -> bool {
    // In-memory test sessions have no filesystem location.
    if db.path().is_none_or(str::is_empty) {
        return false;
    }
    let now = Utc::now();
    let health = storage::local(db, HEALTH)
        .ok()
        .flatten()
        .unwrap_or_default();
    if reason == "automatic" && health["retryAfter"].as_i64().unwrap_or(0) > now.timestamp() {
        return false;
    }
    match take(db, reason, now, Local::now().date_naive(), SIZE_CAP) {
        Ok(entry) => {
            if entry.is_some() {
                let _ = storage::put_local(db, HEALTH, &serde_json::json!({"failures":0}));
            }
            entry.is_some()
        }
        Err(_) => {
            let failures = health["failures"].as_u64().unwrap_or(0).saturating_add(1);
            let _ = storage::put_local(
                db,
                HEALTH,
                &serde_json::json!({"failures":failures,"retryAfter":now.timestamp()+3600}),
            );
            false
        }
    }
}

fn take(
    db: &mut Connection,
    reason: &str,
    now: DateTime<Utc>,
    day: NaiveDate,
    cap: u64,
) -> Result<Option<Entry>, String> {
    let entries = list(db)?;
    if reason == "automatic" && entries.iter().any(|e| e.day >= day.to_string()) {
        return Ok(None);
    }
    // Use the same conflict check, canonical validation and omission policy as manual export.
    let values = storage::backup_recipes(db)?;
    let current = storage::snapshot(db)?;
    let recipes = values
        .iter()
        .map(|r| Recipe::from_json(&serde_json::to_vec(r).map_err(err)?).map_err(err))
        .collect::<Result<Vec<_>, String>>()?;
    let bytes =
        backup::write_with_setup(&recipes, Some(&current.book.shopping_setup)).map_err(err)?;
    let fingerprint = format!("{:x}", Sha256::digest(&bytes));
    if reason == "automatic"
        && (entries.last().is_some_and(|e| e.fingerprint == fingerprint)
            || (entries.is_empty() && recipes.is_empty()))
    {
        prune(db, &entries, day, cap)?;
        return Ok(None);
    }
    if bytes.len() as u64 > cap && reason != "before_restore" {
        return Err("Snapshot exceeds storage cap".into());
    }
    let entry = Entry {
        id: uuid::Uuid::new_v4().to_string(),
        created_at: now.to_rfc3339_opts(chrono::SecondsFormat::Nanos, true),
        day: day.to_string(),
        recipe_count: recipes.len() as u32,
        omitted_count: current.set_aside.len() as u32,
        reason: reason.into(),
        bytes: bytes.len() as u64,
        fingerprint,
    };
    let root = directory(db)?;
    fs::create_dir_all(&root).map_err(err)?;
    let staging = root.join(format!(".{}", entry.id));
    fs::create_dir(&staging).map_err(err)?;
    let write = || -> Result<(), String> {
        for (name, data) in [
            ("snapshot.zip", bytes),
            ("info.json", serde_json::to_vec(&entry).map_err(err)?),
        ] {
            let mut file = fs::File::create(staging.join(name)).map_err(err)?;
            file.write_all(&data).map_err(err)?;
            file.sync_all().map_err(err)?;
        }
        fs::rename(&staging, root.join(&entry.id)).map_err(err)
    };
    if let Err(error) = write() {
        let _ = fs::remove_dir_all(&staging);
        return Err(error);
    }
    let mut entries = entries;
    entries.push(entry.clone());
    prune(db, &entries, day, cap)?;
    Ok(Some(entry))
}

/// Keep newest per calendar day, then newest per ISO week before that window.
/// The most recent pre-restore archive is protected until a newer archive exists.
fn retained(entries: &[Entry], day: NaiveDate, cap: u64) -> HashSet<String> {
    let mut keep = HashSet::new();
    let mut days = HashSet::new();
    let mut weeks = HashSet::new();
    let protected = entries
        .last()
        .filter(|e| e.reason == "before_restore")
        .map(|e| &e.id);
    // An unchanged library must not age out its last recovery point.
    if let Some(latest) = entries.last() {
        keep.insert(latest.id.clone());
    }
    for e in entries.iter().rev() {
        let age = day
            .signed_duration_since(e.day.parse::<NaiveDate>().expect("validated date"))
            .num_days();
        let week = e
            .day
            .parse::<NaiveDate>()
            .expect("validated date")
            .iso_week();
        if (age < 7 && days.insert(e.day.clone()))
            || (age >= 7 && age < 35 && weeks.len() < 4 && weeks.insert((week.year(), week.week())))
            || protected == Some(&e.id)
        {
            keep.insert(e.id.clone());
        }
    }
    let mut size: u64 = entries
        .iter()
        .filter(|e| keep.contains(&e.id))
        .map(|e| e.bytes)
        .sum();
    for e in entries {
        if size <= cap {
            break;
        }
        if protected != Some(&e.id) && keep.remove(&e.id) {
            size -= e.bytes;
        }
    }
    keep
}
fn prune(db: &Connection, entries: &[Entry], day: NaiveDate, cap: u64) -> Result<(), String> {
    let keep = retained(entries, day, cap);
    let root = directory(db)?;
    for e in entries {
        if !keep.contains(&e.id) {
            fs::remove_dir_all(root.join(&e.id)).map_err(err)?;
        }
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{
        adapters::AppPaths,
        services::{Operation, Service},
    };
    struct Root(PathBuf);
    impl Root {
        fn new() -> Self {
            Self(std::env::temp_dir().join(format!("cookdex-snapshots-{}", uuid::Uuid::new_v4())))
        }
    }
    impl AppPaths for Root {
        fn private_root(&self) -> Result<PathBuf, String> {
            Ok(self.0.clone())
        }
    }
    impl Drop for Root {
        fn drop(&mut self) {
            let _ = fs::remove_dir_all(&self.0);
        }
    }
    fn db(root: &Root) -> Connection {
        fs::create_dir_all(root.0.join("flutter-v1")).unwrap();
        storage::open(&root.0.join("flutter-v1/cookdex.sqlite3")).unwrap()
    }
    fn fixture() -> storage::Book {
        serde_json::from_str(include_str!("../tests/native-fixture.json")).unwrap()
    }
    fn clock(days: i64) -> DateTime<Utc> {
        "2026-01-01T12:00:00Z".parse::<DateTime<Utc>>().unwrap() + chrono::Duration::days(days)
    }
    fn capture(db: &mut Connection, day: i64, reason: &str, cap: u64) -> Option<Entry> {
        take(db, reason, clock(day), clock(day).date_naive(), cap).unwrap()
    }
    #[test]
    fn daily_skip_change_detection_and_last_copy_survives_idle() {
        let root = Root::new();
        let mut db = db(&root);
        let mut book = fixture();
        storage::save(&mut db, 0, &book, "seed").unwrap();
        let first = capture(&mut db, 0, "automatic", SIZE_CAP).unwrap();
        book.recipes[0]["notes"] = serde_json::json!("changed");
        storage::save(&mut db, 1, &book, "edit").unwrap();
        assert!(capture(&mut db, 0, "automatic", SIZE_CAP).is_none());
        let second = capture(&mut db, 1, "automatic", SIZE_CAP).unwrap();
        assert_ne!(first.fingerprint, second.fingerprint);
        assert!(capture(&mut db, 2, "automatic", SIZE_CAP).is_none());
        assert!(capture(&mut db, 90, "automatic", SIZE_CAP).is_none());
        assert_eq!(list(&db).unwrap().len(), 1);
        assert_eq!(list(&db).unwrap()[0].id, second.id);
    }
    #[test]
    fn retention_keeps_seven_daily_and_four_weekly_and_prunes_oldest_for_cap() {
        let root = Root::new();
        let mut db = db(&root);
        let mut book = fixture();
        for day in 0..60 {
            book.recipes[0]["notes"] = serde_json::json!(format!("day {day}"));
            storage::save(&mut db, day, &book, "edit").unwrap();
            capture(&mut db, day, "automatic", SIZE_CAP).unwrap();
        }
        let entries = list(&db).unwrap();
        assert_eq!(entries.len(), 11);
        let recent: Vec<_> = entries
            .iter()
            .filter(|e| {
                clock(59)
                    .date_naive()
                    .signed_duration_since(e.day.parse::<NaiveDate>().unwrap())
                    .num_days()
                    < 7
            })
            .collect();
        assert_eq!(recent.len(), 7);
        let weeks: HashSet<_> = entries
            .iter()
            .filter(|e| !recent.iter().any(|r| r.id == e.id))
            .map(|e| e.day.parse::<NaiveDate>().unwrap().iso_week())
            .collect();
        assert_eq!(weeks.len(), 4);
        let cap = entries.iter().rev().take(2).map(|e| e.bytes).sum();
        prune(&db, &entries, clock(59).date_naive(), cap).unwrap();
        let left = list(&db).unwrap();
        assert_eq!(left.len(), 2);
        assert_eq!(left[1].id, entries.last().unwrap().id);
    }
    #[test]
    fn pre_restore_is_protected_even_over_cap_until_newer_snapshot() {
        let root = Root::new();
        let mut db = db(&root);
        storage::save(&mut db, 0, &fixture(), "seed").unwrap();
        let before = capture(&mut db, 0, "before_restore", 1).unwrap();
        prune(&db, &list(&db).unwrap(), clock(100).date_naive(), 1).unwrap();
        assert_eq!(list(&db).unwrap()[0].id, before.id);
        let newer = capture(&mut db, 101, "before_discard", SIZE_CAP).unwrap();
        assert_eq!(list(&db).unwrap().len(), 1);
        assert_eq!(list(&db).unwrap()[0].id, newer.id);
    }
    #[test]
    fn oversize_failure_preserves_prior_archive_and_secret_local_state_is_excluded() {
        let root = Root::new();
        let mut db = db(&root);
        storage::save(&mut db, 0, &fixture(), "seed").unwrap();
        storage::put_local(
            &db,
            "geminiTest",
            &serde_json::json!("synthetic-secret-marker"),
        )
        .unwrap();
        storage::put_local(
            &db,
            "syncConfig",
            &serde_json::json!({"key":"synthetic-pair-marker"}),
        )
        .unwrap();
        let first = capture(&mut db, 0, "automatic", SIZE_CAP).unwrap();
        let bytes = read(&db, &first.id).unwrap();
        assert!(!String::from_utf8_lossy(&bytes).contains("synthetic-secret-marker"));
        assert!(!String::from_utf8_lossy(&bytes).contains("synthetic-pair-marker"));
        let (recipes, setup) = backup::read_with_setup(&bytes).unwrap();
        assert_eq!(recipes.len(), fixture().recipes.len());
        assert!(setup.is_some());
        assert!(
            take(
                &mut db,
                "before_discard",
                clock(1),
                clock(1).date_naive(),
                1
            )
            .is_err()
        );
        assert_eq!(list(&db).unwrap()[0].id, first.id);
        assert!(read(&db, "../elsewhere").is_err());
    }
    #[test]
    fn first_sync_is_once_per_pairing_and_before_changes() {
        let root = Root::new();
        let mut db = db(&root);
        let book = fixture();
        storage::save(&mut db, 0, &book, "seed").unwrap();
        before_sync(&mut db, "synthetic-pair");
        let first = list(&db).unwrap()[0].clone();
        storage::save(&mut db, 1, &storage::Book::default(), "delete").unwrap();
        before_sync(&mut db, "synthetic-pair");
        assert_eq!(list(&db).unwrap()[0].id, first.id);
        assert_eq!(
            backup::read(&read(&db, &first.id).unwrap()).unwrap().len(),
            book.recipes.len()
        );
        before_sync(&mut db, "another-pair");
        assert_ne!(list(&db).unwrap().last().unwrap().id, first.id);
    }
    #[test]
    fn restore_and_discard_hooks_and_damaged_current_recipe_recovery() {
        let root = Root::new();
        let service = Service::open(&root).unwrap();
        let recipes: Vec<_> = fixture()
            .recipes
            .iter()
            .map(|r| Recipe::from_json(&serde_json::to_vec(r).unwrap()).unwrap())
            .collect();
        let bytes = backup::write(&recipes).unwrap();
        service
            .restore(
                &service
                    .preview_restore(&bytes, &Operation::default())
                    .unwrap(),
                &Operation::default(),
            )
            .unwrap();
        let mut db = db(&root);
        assert_eq!(list(&db).unwrap().last().unwrap().reason, "before_restore");
        // Capture good contents without depending on the machine's current day.
        let good = take(
            &mut db,
            "before_first_sync",
            Utc::now(),
            Local::now().date_naive(),
            SIZE_CAP,
        )
        .unwrap()
        .unwrap();
        db.execute("UPDATE recipes SET body='not json'", [])
            .unwrap();
        let listing = service.rolling_snapshots().unwrap();
        assert!(!listing.0.is_empty());
        let preview = service
            .preview_restore(
                &service.rolling_snapshot_bytes(&good.id).unwrap(),
                &Operation::default(),
            )
            .unwrap();
        let restored = service.restore(&preview, &Operation::default()).unwrap();
        assert_eq!(restored.set_aside_count, 0);
        assert_eq!(restored.summaries.len(), recipes.len());
        db.execute("UPDATE recipes SET body='not json'", [])
            .unwrap();
        service
            .discard_set_aside(restored.generation, &Operation::default())
            .unwrap();
        let entries = list(&db).unwrap();
        assert!(
            entries
                .iter()
                .any(|e| e.reason == "before_discard" && e.omitted_count == recipes.len() as u32)
        );
    }
    #[test]
    fn repeated_snapshot_failure_does_not_block_save_or_restore() {
        let root = Root::new();
        let service = Service::open(&root).unwrap();
        let db = db(&root);
        fs::write(directory(&db).unwrap(), b"simulate unavailable directory").unwrap();
        let recipe =
            Recipe::from_json(&serde_json::to_vec(&fixture().recipes[0]).unwrap()).unwrap();
        let saved = service
            .save(0, None, recipe.content.clone(), &Operation::default())
            .unwrap();
        assert_eq!(saved.summaries.len(), 1);
        for _ in 0..3 {
            let zip = backup::write(&[recipe.clone()]).unwrap();
            let preview = service
                .preview_restore(&zip, &Operation::default())
                .unwrap();
            service.restore(&preview, &Operation::default()).unwrap();
        }
        assert!(repeatedly_failing(&db));
        assert!(service.rolling_snapshots().is_err());
        assert!(service.rolling_snapshot_maintenance());
        assert!(!service.snapshot().unwrap().summaries.is_empty());
    }
}
