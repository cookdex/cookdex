use rusqlite::{Connection, OptionalExtension, TransactionBehavior, params};
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};
use std::{collections::HashSet, path::Path, time::Duration};
use uuid::Uuid;

#[derive(Clone, Debug, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct Book {
    pub schema_version: u32,
    pub recipes: Vec<Value>,
    pub shopping: Vec<Value>,
    #[serde(default)]
    pub shopping_setup: crate::shopping_categories::Setup,
    pub deleted_recipes: Vec<Value>,
}
impl Default for Book {
    fn default() -> Self {
        Self {
            schema_version: 1,
            recipes: vec![],
            shopping: vec![],
            shopping_setup: Default::default(),
            deleted_recipes: vec![],
        }
    }
}
#[derive(Serialize)]
pub struct Snapshot {
    pub generation: i64,
    pub book: Book,
    pub set_aside: Vec<String>,
}

// Distinguishes Flutter-owned databases even if an old file is put at our path.
const APPLICATION_ID: i64 = 0x43445846; // CDXF
pub fn open(path: &Path) -> Result<Connection, String> {
    let mut db = Connection::open(path).map_err(err)?;
    db.busy_timeout(Duration::from_secs(5)).map_err(err)?;
    db.execute_batch("PRAGMA foreign_keys=ON; PRAGMA synchronous=FULL;")
        .map_err(err)?;
    let tx = db
        .transaction_with_behavior(TransactionBehavior::Immediate)
        .map_err(err)?;
    let version: i64 = tx
        .query_row("PRAGMA user_version", [], |r| r.get(0))
        .map_err(err)?;
    let owner: i64 = tx
        .query_row("PRAGMA application_id", [], |r| r.get(0))
        .map_err(err)?;
    let tables: i64 = tx
        .query_row("SELECT count(*) FROM sqlite_master", [], |r| r.get(0))
        .map_err(err)?;
    if version == 0 && owner == 0 && tables == 0 {
        tx.execute_batch("CREATE TABLE state (id INTEGER PRIMARY KEY CHECK(id=1), generation INTEGER NOT NULL, device_id TEXT NOT NULL);
            CREATE TABLE recipes (id TEXT PRIMARY KEY, body TEXT NOT NULL, revision_id TEXT NOT NULL);
            CREATE TABLE local (key TEXT PRIMARY KEY, body TEXT NOT NULL);
            CREATE TABLE heads (recipe_id TEXT PRIMARY KEY, revision_id TEXT NOT NULL);
            CREATE TABLE history (id TEXT PRIMARY KEY, recipe_id TEXT NOT NULL, body TEXT NOT NULL);
            PRAGMA user_version=2;
            PRAGMA application_id=1128552518;").map_err(err)?;
        tx.execute(
            "INSERT INTO state VALUES(1,0,?1)",
            [Uuid::new_v4().to_string()],
        )
        .map_err(err)?;
    } else if owner != APPLICATION_ID || version != 2 {
        return Err("Unsupported or non-Flutter database; data was not changed.".into());
    }
    tx.query_row("SELECT generation FROM state WHERE id=1", [], |r| {
        r.get::<_, i64>(0)
    })
    .map_err(err)?;
    tx.commit().map_err(err)?;
    Ok(db)
}

fn err(e: impl std::fmt::Display) -> String {
    e.to_string()
}
pub(crate) fn local(db: &Connection, key: &str) -> Result<Option<Value>, String> {
    let value: Option<String> = db
        .query_row("SELECT body FROM local WHERE key=?1", [key], |r| r.get(0))
        .optional()
        .map_err(err)?;
    value
        .map(|s| serde_json::from_str(&s).map_err(err))
        .transpose()
}
pub(crate) fn put_local(db: &Connection, key: &str, value: &Value) -> Result<(), String> {
    db.execute(
        "INSERT INTO local VALUES(?1,?2) ON CONFLICT(key) DO UPDATE SET body=excluded.body",
        params![key, value.to_string()],
    )
    .map_err(err)?;
    Ok(())
}
// Validate a copy only: schema migration in the typed view must never change
// immutable history payloads or their digests.
pub(crate) fn validate_recipe(value: &Value) -> Result<(), String> {
    crate::recipe::Recipe::from_json(&serde_json::to_vec(value).map_err(err)?)
        .map(|_| ())
        .map_err(err)
}
fn readable_recipes(db: &Connection) -> Result<(Vec<Value>, Vec<String>), String> {
    let mut statement = db
        .prepare("SELECT id,body FROM recipes ORDER BY id")
        .map_err(err)?;
    let rows = statement
        .query_map([], |r| Ok((r.get::<_, String>(0)?, r.get::<_, String>(1)?)))
        .map_err(err)?;
    let mut recipes = vec![];
    let mut set_aside = vec![];
    for row in rows {
        let (id, body) = row.map_err(err)?;
        match serde_json::from_str::<Value>(&body) {
            Ok(value) if value["id"] == id && validate_recipe(&value).is_ok() => {
                recipes.push(value)
            }
            _ => set_aside.push(id),
        }
    }
    // The projection can still be readable when its current history payload
    // was damaged. Keep compaction from turning that one recipe into a load
    // failure, and retain its ancestry for an explicit restore/discard.
    let mut heads = db
        .prepare("SELECT h.recipe_id,h.body FROM history h JOIN heads p ON p.revision_id=h.id")
        .map_err(err)?;
    let rows = heads
        .query_map([], |r| Ok((r.get::<_, String>(0)?, r.get::<_, String>(1)?)))
        .map_err(err)?;
    for row in rows {
        let (id, body) = row.map_err(err)?;
        let event: crate::sync_store::Event = serde_json::from_str(&body).map_err(err)?;
        if event
            .recipe
            .as_ref()
            .is_some_and(|r| r["id"] != id || validate_recipe(r).is_err())
        {
            set_aside.push(id);
        }
    }
    // A corrupt conflict alternative must not break the typed conflict reader.
    if let Some(conflicts) = local(db, "syncConflicts")? {
        for conflict in conflicts.as_array().ok_or("Invalid conflict state")? {
            if conflict["versions"]
                .as_array()
                .ok_or("Invalid conflict versions")?
                .iter()
                .any(|v| !v["recipe"].is_null() && validate_recipe(&v["recipe"]).is_err())
            {
                let id = conflict["recipeId"]
                    .as_str()
                    .ok_or("Invalid conflict identity")?
                    .to_owned();
                recipes.retain(|r| r["id"] != id);
                set_aside.push(id);
            }
        }
    }
    set_aside.sort();
    set_aside.dedup();
    recipes.retain(|r| !set_aside.iter().any(|id| r["id"] == *id));
    Ok((recipes, set_aside))
}
pub(crate) fn set_aside_ids(db: &Connection) -> Result<Vec<String>, String> {
    Ok(readable_recipes(db)?.1)
}
pub(crate) fn snapshot(db: &Connection) -> Result<Snapshot, String> {
    let generation = db
        .query_row("SELECT generation FROM state WHERE id=1", [], |r| r.get(0))
        .map_err(err)?;
    let (recipes, set_aside) = readable_recipes(db)?;
    let book = Book {
        recipes,
        shopping: serde_json::from_value(local(db, "shopping")?.unwrap_or(json!([])))
            .map_err(err)?,
        shopping_setup: local(db, "shoppingSetup")?
            .map(serde_json::from_value)
            .transpose()
            .map_err(err)?
            .unwrap_or_default(),
        deleted_recipes: serde_json::from_value(local(db, "deletedRecipes")?.unwrap_or(json!([])))
            .map_err(err)?,
        ..Book::default()
    };
    validate(&book)?;
    Ok(Snapshot {
        generation,
        book,
        set_aside,
    })
}
pub fn load(db: &mut Connection) -> Result<Snapshot, String> {
    let tx = db
        .transaction_with_behavior(TransactionBehavior::Immediate)
        .map_err(err)?;
    crate::sync_store::compact(&tx)?;
    let result = snapshot(&tx)?;
    tx.commit().map_err(err)?;
    Ok(result)
}
pub fn previous(db: &Connection) -> Result<Option<Value>, String> {
    local(db, "previous")
}

// Check conflicts and read recipes in one snapshot, so a concurrent sync cannot
// make a successful backup silently omit an unresolved alternative version.
pub fn backup_recipes(db: &mut Connection) -> Result<Vec<Value>, String> {
    let tx = db.transaction().map_err(err)?;
    let conflicts = crate::sync_store::conflicts(&tx)?;
    if !conflicts
        .as_array()
        .ok_or("Invalid conflict state")?
        .is_empty()
    {
        return Err(
            "Resolve sync conflicts in Backups & sync before creating a recipe backup.".into(),
        );
    }
    let recipes = snapshot(&tx)?.book.recipes;
    tx.commit().map_err(err)?;
    Ok(recipes)
}

pub(crate) fn validate(book: &Book) -> Result<(), String> {
    book.shopping_setup.validate().map_err(err)?;
    if book.schema_version != 1 || book.recipes.len() > 10000 {
        return Err("Unsupported or oversized collection.".into());
    }
    let mut ids = HashSet::new();
    for r in &book.recipes {
        validate_recipe(r)?;
        if !ids.insert(r["id"].as_str().ok_or("Missing recipe ID")?) {
            return Err("Duplicate recipe identity.".into());
        }
    }
    let mut legacy_size = serde_json::to_value(book).map_err(err)?;
    legacy_size
        .as_object_mut()
        .ok_or("Invalid collection")?
        .remove("shoppingSetup");
    if serde_json::to_vec(&legacy_size).map_err(err)?.len() > 32 * 1024 * 1024 {
        return Err("Collection exceeds 32 MB native save limit.".into());
    }
    Ok(())
}

pub fn save(
    db: &mut Connection,
    expected: i64,
    book: &Book,
    saved_at: &str,
) -> Result<i64, String> {
    save_inner(db, expected, book, saved_at, false)
}
fn save_inner(
    db: &mut Connection,
    expected: i64,
    book: &Book,
    saved_at: &str,
    fail_before_commit: bool,
) -> Result<i64, String> {
    validate(book)?;
    let tx = db
        .transaction_with_behavior(TransactionBehavior::Immediate)
        .map_err(err)?;
    let old = snapshot(&tx)?;
    if old.generation != expected {
        return Err("STALE_WRITE: collection changed; reload before saving.".into());
    }
    if old.set_aside.is_empty() {
        put_local(
            &tx,
            "previous",
            &json!({"savedAt":saved_at,"book":old.book}),
        )?;
    }
    let conflicts = crate::sync_store::conflicts(&tx)?;
    for c in conflicts.as_array().ok_or("Invalid conflict state")? {
        let id = &c["recipeId"];
        if old.book.recipes.iter().find(|r| &r["id"] == id)
            != book.recipes.iter().find(|r| &r["id"] == id)
        {
            return Err(
                "Resolve this recipe’s sync conflict in Backups & sync before editing it.".into(),
            );
        }
    }
    let ids: HashSet<&str> = book
        .recipes
        .iter()
        .map(|r| r["id"].as_str().unwrap())
        .collect();
    for recipe in &book.recipes {
        if old.book.recipes.contains(recipe) {
            continue;
        }
        let id = recipe["id"].as_str().unwrap();
        let rev = record(&tx, id, json!({"kind":"put","recipe":recipe}))?;
        tx.execute("INSERT INTO recipes VALUES(?1,?2,?3) ON CONFLICT(id) DO UPDATE SET body=excluded.body,revision_id=excluded.revision_id", params![id,recipe.to_string(),rev]).map_err(err)?;
    }
    for recipe in &old.book.recipes {
        let id = recipe["id"].as_str().unwrap();
        if !ids.contains(id) {
            let deleted_at = book
                .deleted_recipes
                .iter()
                .find(|d| d["id"] == id)
                .and_then(|d| d["deletedAt"].as_str())
                .unwrap_or(saved_at);
            record(&tx, id, json!({"kind":"delete","deletedAt":deleted_at}))?;
            tx.execute("DELETE FROM recipes WHERE id=?1", [id])
                .map_err(err)?;
        }
    }
    let mut conflicts = local(&tx, "syncConflicts")?.unwrap_or(json!([]));
    conflicts
        .as_array_mut()
        .ok_or("Invalid conflict state")?
        .retain(|c| {
            !old.set_aside
                .iter()
                .any(|id| c["recipeId"] == *id && ids.contains(id.as_str()))
        });
    put_local(&tx, "syncConflicts", &conflicts)?;
    put_local(&tx, "shopping", &json!(book.shopping))?;
    put_local(&tx, "shoppingSetup", &json!(book.shopping_setup))?;
    put_local(&tx, "deletedRecipes", &json!(book.deleted_recipes))?;
    let generation = expected.checked_add(1).ok_or("Generation overflow")?;
    tx.execute("UPDATE state SET generation=?1 WHERE id=1", [generation])
        .map_err(err)?;
    crate::sync_store::compact(&tx)?;
    if fail_before_commit {
        return Err("Injected failure before commit".into());
    }
    tx.commit().map_err(err)?;
    Ok(generation)
}
fn record(db: &Connection, recipe_id: &str, mut event: Value) -> Result<String, String> {
    let parent: Option<String> = db
        .query_row(
            "SELECT revision_id FROM heads WHERE recipe_id=?1",
            [recipe_id],
            |r| r.get(0),
        )
        .optional()
        .map_err(err)?;
    let id = Uuid::new_v4().to_string();
    event["id"] = json!(id);
    event["recipeId"] = json!(recipe_id);
    let mut parents: Vec<String> = parent.into_iter().collect();
    if let Some(conflicts) = local(db, "syncConflicts")? {
        for c in conflicts.as_array().ok_or("Invalid conflict state")? {
            if c["recipeId"] == recipe_id {
                for v in c["versions"]
                    .as_array()
                    .ok_or("Invalid conflict versions")?
                {
                    parents.push(v["id"].as_str().ok_or("Invalid conflict revision")?.into());
                }
            }
        }
    }
    parents.sort();
    parents.dedup();
    event["parents"] = json!(parents);
    db.execute(
        "INSERT INTO history VALUES(?1,?2,?3)",
        params![id, recipe_id, event.to_string()],
    )
    .map_err(err)?;
    db.execute("INSERT INTO heads VALUES(?1,?2) ON CONFLICT(recipe_id) DO UPDATE SET revision_id=excluded.revision_id", params![recipe_id,id]).map_err(err)?;
    Ok(id)
}

// Only an explicit, generation-bound confirmation may discard unreadable rows.
pub fn discard_set_aside(db: &mut Connection, expected: i64, saved_at: &str) -> Result<(), String> {
    let tx = db
        .transaction_with_behavior(TransactionBehavior::Immediate)
        .map_err(err)?;
    let old = snapshot(&tx)?;
    if old.generation != expected {
        return Err("STALE_WRITE: collection changed; reload before discarding.".into());
    }
    if old.set_aside.is_empty() {
        return Ok(());
    }
    let mut deletions = old.book.deleted_recipes;
    for id in &old.set_aside {
        record(&tx, id, json!({"kind":"delete","deletedAt":saved_at}))?;
        tx.execute("DELETE FROM recipes WHERE id=?1", [id])
            .map_err(err)?;
        deletions.retain(|d| d["id"] != *id);
        deletions.push(json!({"id":id,"deletedAt":saved_at}));
    }
    let mut conflicts = local(&tx, "syncConflicts")?.unwrap_or(json!([]));
    conflicts
        .as_array_mut()
        .ok_or("Invalid conflict state")?
        .retain(|c| !old.set_aside.iter().any(|id| c["recipeId"] == *id));
    put_local(&tx, "syncConflicts", &conflicts)?;
    put_local(&tx, "deletedRecipes", &json!(deletions))?;
    tx.execute("UPDATE state SET generation=generation+1 WHERE id=1", [])
        .map_err(err)?;
    crate::sync_store::compact(&tx)?;
    tx.commit().map_err(err)
}

#[cfg(test)]
mod tests {
    use super::*;
    fn fixture() -> Book {
        serde_json::from_str(include_str!("../tests/native-fixture.json")).unwrap()
    }
    #[test]
    fn future_version_and_missing_marker_fail_closed() {
        let path = std::env::temp_dir().join(format!("recipe-version-{}.sqlite", Uuid::new_v4()));
        {
            let db = open(&path).unwrap();
            db.execute_batch("PRAGMA user_version=99").unwrap();
        }
        assert!(open(&path).is_err());
        {
            let db = Connection::open(&path).unwrap();
            db.execute_batch("PRAGMA user_version=2; DELETE FROM state")
                .unwrap();
        }
        assert!(open(&path).is_err());
        std::fs::remove_file(path).unwrap();
    }
    #[test]
    fn persistence_rename_conflict_rollback_and_recovery() {
        let path = std::env::temp_dir().join(format!("recipe-test-{}.sqlite", Uuid::new_v4()));
        {
            let mut db = open(&path).unwrap();
            let initial = fixture();
            assert_eq!(save(&mut db, 0, &initial, "first").unwrap(), 1);
            drop(db);
            let mut db = open(&path).unwrap();
            assert_eq!(load(&mut db).unwrap().book, initial);
            let mut other = open(&path).unwrap();
            assert_eq!(load(&mut other).unwrap().generation, 1);
            let mut renamed = initial.clone();
            renamed.recipes[0]["title"] = json!("Renamed");
            save(&mut db, 1, &renamed, "second").unwrap();
            assert!(
                save(&mut other, 1, &initial, "stale")
                    .unwrap_err()
                    .contains("STALE_WRITE")
            );
            assert!(save_inner(&mut db, 2, &initial, "failure", true).is_err());
            let stored = load(&mut db).unwrap();
            assert_eq!(stored.generation, 2);
            assert_eq!(stored.book, renamed);
            assert_eq!(previous(&db).unwrap().unwrap()["book"], json!(initial));
            let count: i64 = db
                .query_row("SELECT count(*) FROM recipes", [], |r| r.get(0))
                .unwrap();
            assert_eq!(count, 1);
            let events: i64 = db
                .query_row("SELECT count(*) FROM history", [], |r| r.get(0))
                .unwrap();
            assert_eq!(events, 2);
            save(&mut db, 2, &Book::default(), "delete").unwrap();
            save(&mut db, 3, &renamed, "recover").unwrap();
            let event: String = db
                .query_row(
                    "SELECT h.body FROM history h JOIN heads ON heads.revision_id=h.id",
                    [],
                    |r| r.get(0),
                )
                .unwrap();
            let parent = serde_json::from_str::<Value>(&event).unwrap()["parents"][0]
                .as_str()
                .unwrap()
                .to_owned();
            let deleted: String = db
                .query_row("SELECT body FROM history WHERE id=?1", [parent], |r| {
                    r.get(0)
                })
                .unwrap();
            assert_eq!(
                serde_json::from_str::<Value>(&deleted).unwrap()["kind"],
                "delete"
            );
        }
        std::fs::remove_file(path).unwrap();
    }
    #[test]
    fn bad_fraction_and_malformed_storage_never_replace_data() {
        let mut db = open(Path::new(":memory:")).unwrap();
        let initial = fixture();
        save(&mut db, 0, &initial, "first").unwrap();
        let mut invalid = initial.clone();
        invalid.recipes[0]["ingredients"][0]["amount"]["denominator"] = json!(0);
        assert!(save(&mut db, 1, &invalid, "bad").is_err());
        assert_eq!(load(&mut db).unwrap().book, initial);
        db.execute("UPDATE recipes SET body='not json'", [])
            .unwrap();
        let unreadable = load(&mut db).unwrap();
        assert!(unreadable.book.recipes.is_empty());
        assert_eq!(unreadable.set_aside.len(), 1);
        save(&mut db, 1, &initial, "restore").unwrap();
        assert_eq!(load(&mut db).unwrap().book, initial);
    }
}

#[cfg(test)]
mod compaction_transaction_tests {
    use super::*;
    use crate::sync_store;
    fn fixture() -> Book {
        serde_json::from_str(include_str!("../tests/native-fixture.json")).unwrap()
    }
    #[test]
    fn failed_save_restores_payloads_previous_projection_and_generation() {
        let mut db = open(Path::new(":memory:")).unwrap();
        let mut book = fixture();
        save(&mut db, 0, &book, "first").unwrap();
        for n in 0..3 {
            book.recipes[0]["notes"] = json!(format!("edit{n}"));
            save(&mut db, n + 1, &book, "next").unwrap();
        }
        let original = sync_store::export(&db).unwrap().events;
        assert_eq!(original.iter().filter(|e| e.recipe.is_some()).count(), 4);
        let previous_value = previous(&db).unwrap();
        book.recipes[0]["notes"] = json!("must not commit");
        assert!(save_inner(&mut db, 4, &book, "fail", true).is_err());
        assert_eq!(sync_store::export(&db).unwrap().events, original);
        assert_eq!(previous(&db).unwrap(), previous_value);
        let restored = load(&mut db).unwrap();
        assert_eq!(restored.generation, 4);
        assert_eq!(restored.book.recipes[0]["notes"], "edit2");
    }
}
