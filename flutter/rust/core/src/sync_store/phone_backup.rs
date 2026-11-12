//! Portable Android backup. Revision IDs and parent links travel with the
//! recipes so a restored phone can join an existing library as a new peer.
use super::*;
use flate2::{Compression, read::GzDecoder, write::GzEncoder};
use std::io::Read;

pub const CLOUD_LIMIT: usize = 20 * 1024 * 1024;
const RAW_LIMIT: usize = 140 * 1024 * 1024;

#[cfg(target_os = "android")]
pub fn write_to_files(database: i32, output: i32) -> Result<(), String> {
    use std::io::Write;
    use std::os::fd::{BorrowedFd, OwnedFd};
    // ParcelFileDescriptor owns both descriptors throughout the synchronous call.
    let database_path = std::fs::read_link(format!("/proc/self/fd/{database}")).map_err(err)?;
    let mut db =
        Connection::open_with_flags(database_path, rusqlite::OpenFlags::SQLITE_OPEN_READ_ONLY)
            .map_err(err)?;
    // Duplicate the output so closing Rust's File cannot close Kotlin's handle.
    let fd: OwnedFd = unsafe { BorrowedFd::borrow_raw(output) }
        .try_clone_to_owned()
        .map_err(err)?;
    let mut file = std::fs::File::from(fd);
    file.write_all(&encode(&mut db)?).map_err(err)?;
    file.sync_all().map_err(err)
}

#[derive(Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
struct PhoneLibrary {
    version: u32,
    history: Packet,
    selected: BTreeMap<String, String>,
    shopping: Vec<crate::shopping::Item>,
    shopping_setup: crate::shopping_categories::Setup,
}

pub fn encode(db: &mut Connection) -> Result<Vec<u8>, String> {
    let tx = db.transaction().map_err(err)?;
    let snapshot = storage::snapshot(&tx)?;
    let mut history = export(&tx)?;
    let selected = {
        let mut query = tx
            .prepare("SELECT recipe_id,revision_id FROM heads")
            .map_err(err)?;
        query
            .query_map([], |r| Ok((r.get(0)?, r.get(1)?)))
            .map_err(err)?
            .collect::<rusqlite::Result<BTreeMap<_, _>>>()
            .map_err(err)?
    };
    let (events, heads) = graph(history.events.clone())?;
    if selected.len() != heads.len() || !snapshot.set_aside.is_empty() {
        return Err("Incomplete recipe history.".into());
    }
    let visible: BTreeMap<_, _> = snapshot
        .book
        .recipes
        .iter()
        .map(|r| (r["id"].as_str().unwrap(), r))
        .collect();
    let mut keep = BTreeSet::new();
    for (recipe, heads) in &heads {
        let choice = selected
            .get(recipe)
            .filter(|id| heads.contains(id))
            .ok_or("Invalid selected revision.")?;
        if visible.get(recipe.as_str()).copied() != events[choice].recipe.as_ref() {
            return Err("Recipe and history disagree.".into());
        }
        keep.extend(heads.iter().cloned());
    }
    if visible.keys().any(|id| !selected.contains_key(*id)) {
        return Err("Missing recipe history.".into());
    }
    for event in &mut history.events {
        if event.recipe.is_some() && !keep.contains(&event.id) {
            event.recipe_digest = payload_digest(event)?;
            event.recipe = None;
        }
    }
    let library = PhoneLibrary {
        version: 1,
        history,
        selected,
        shopping: serde_json::from_value(json!(snapshot.book.shopping)).map_err(err)?,
        shopping_setup: snapshot.book.shopping_setup,
    };
    tx.commit().map_err(err)?;
    let mut writer = GzEncoder::new(Vec::new(), Compression::default());
    serde_json::to_writer(&mut writer, &library).map_err(err)?;
    writer.finish().map_err(err)
}

pub fn restore(db: &mut Connection, bytes: &[u8]) -> Result<(), String> {
    if bytes.len() > RAW_LIMIT {
        return Err("Phone backup exceeds its limit.".into());
    }
    let mut raw = Vec::new();
    GzDecoder::new(bytes)
        .take((RAW_LIMIT + 1) as u64)
        .read_to_end(&mut raw)
        .map_err(err)?;
    if raw.len() > RAW_LIMIT {
        return Err("Phone backup exceeds its limit.".into());
    }
    let library: PhoneLibrary = serde_json::from_slice(&raw).map_err(err)?;
    if library.version != 1 {
        return Err("Unsupported phone backup.".into());
    }
    validate_packet(&library.history)?;
    let (events, heads) = graph(library.history.events)?;
    if heads.len() != library.selected.len() {
        return Err("Incomplete phone backup.".into());
    }
    library.shopping_setup.validate().map_err(err)?;
    crate::shopping::validate(&library.shopping).map_err(err)?;
    let tx = db.transaction().map_err(err)?;
    let fresh: bool = tx.query_row("SELECT generation=0 AND NOT EXISTS(SELECT 1 FROM history)
        AND NOT EXISTS(SELECT 1 FROM recipes) AND NOT EXISTS(SELECT 1 FROM local) FROM state WHERE id=1",
        [], |r| r.get(0)).map_err(err)?;
    if !fresh {
        return Err("Phone restore needs a new library.".into());
    }
    for event in events.values() {
        insert(&tx, event)?;
    }
    let mut deleted = vec![];
    let mut conflicts = vec![];
    for (recipe, versions) in &heads {
        let revision = library
            .selected
            .get(recipe)
            .filter(|id| versions.contains(id))
            .ok_or("Invalid selected revision.")?;
        let event = &events[revision];
        tx.execute(
            "INSERT INTO heads VALUES (?1,?2)",
            params![recipe, revision],
        )
        .map_err(err)?;
        if let Some(body) = &event.recipe {
            tx.execute(
                "INSERT INTO recipes VALUES (?1,?2,?3)",
                params![recipe, body.to_string(), revision],
            )
            .map_err(err)?;
        } else {
            deleted.push(json!({"id":recipe,"deletedAt":event.deleted_at}));
        }
        if versions.len() > 1 {
            conflicts.push(json!({"recipeId":recipe,"versions":versions.iter().map(|id| &events[id]).collect::<Vec<_>>()}));
        }
    }
    storage::put_local(&tx, "shopping", &library.shopping)?;
    storage::put_local(&tx, "shoppingSetup", &library.shopping_setup)?;
    storage::put_local(&tx, "deletedRecipes", &deleted)?;
    storage::put_local(&tx, "syncConflicts", &conflicts)?;
    tx.execute("UPDATE state SET generation=1 WHERE id=1", [])
        .map_err(err)?;
    if !storage::snapshot(&tx)?.set_aside.is_empty() {
        return Err("Invalid restored library.".into());
    }
    tx.commit().map_err(err)
}

/// Materialize a verified, disposable database before Android publishes it.
#[cfg(target_os = "android")]
pub fn restore_to_file(input: i32, database: i32) -> Result<(), String> {
    use std::os::fd::BorrowedFd;
    let input = unsafe { BorrowedFd::borrow_raw(input) }
        .try_clone_to_owned()
        .map_err(err)?;
    let file = std::fs::File::from(input);
    if file.metadata().map_err(err)?.len() > RAW_LIMIT as u64 {
        return Err("Phone backup exceeds its limit.".into());
    }
    let path = std::fs::read_link(format!("/proc/self/fd/{database}")).map_err(err)?;
    let info = std::fs::metadata(&path).map_err(err)?;
    if !info.is_file() || info.len() != 0 {
        return Err("Expected an empty staged database.".into());
    }
    let mut bytes = Vec::new();
    file.take(RAW_LIMIT as u64 + 1)
        .read_to_end(&mut bytes)
        .map_err(err)?;
    let mut db = storage::open(&path)?;
    restore(&mut db, &bytes)?;
    db.close().map_err(|(_, e)| err(e))?;
    std::fs::OpenOptions::new()
        .write(true)
        .open(&path)
        .and_then(|f| f.sync_all())
        .map_err(err)
}
