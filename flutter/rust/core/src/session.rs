//! One session owns the serialized database and host-independent LAN engine.
//! Call blocking work off the UI thread. No database guard crosses a network call.
use crate::{adapters::AppPaths, lan_sync, storage, sync_engine};
use rusqlite::Connection;
use std::sync::{Arc, Mutex, MutexGuard};

pub struct Session {
    db: Arc<Mutex<Connection>>,
    pub(crate) sync: sync_engine::Engine,
}

impl Session {
    pub fn open(paths: &impl AppPaths) -> Result<Self, String> {
        Self::open_with_port(paths, lan_sync::PORT)
    }
    pub fn open_with_port(paths: &impl AppPaths, port: u16) -> Result<Self, String> {
        let root = paths.private_root()?;
        if !root.is_absolute() {
            return Err("An absolute app-private root is required".into());
        }
        // This is the only path. Never probe recipe-book.sqlite3 or legacy stores.
        let directory = root.join("flutter-v1");
        std::fs::create_dir_all(&directory).map_err(|e| e.to_string())?;
        let db = Arc::new(Mutex::new(storage::open(
            &directory.join("cookdex.sqlite3"),
        )?));
        let sync = sync_engine::Engine::new(lan_sync::Service::with_port(db.clone(), port)?);
        Ok(Self { db, sync })
    }

    pub(crate) fn connection(&self) -> Result<MutexGuard<'_, Connection>, String> {
        self.db
            .lock()
            .map_err(|_| "Database lock unavailable".into())
    }

    pub fn load(&self) -> Result<storage::Snapshot, String> {
        storage::load(&mut *self.connection()?)
    }

    // C1 retains the copied internal Book representation. C2/C3 replace the
    // recipe/service boundary with typed domain commands and generated FRB.
    pub fn save(
        &self,
        generation: i64,
        book: &storage::Book,
        saved_at: &str,
    ) -> Result<i64, String> {
        storage::save(&mut *self.connection()?, generation, book, saved_at)
    }

    pub fn device_id(&self) -> Result<String, String> {
        self.connection()?
            .query_row("SELECT device_id FROM state WHERE id=1", [], |r| r.get(0))
            .map_err(|e| e.to_string())
    }

    pub fn foreground(&self, visible: bool) -> Result<(), String> {
        self.sync.host_active(visible)
    }
}
