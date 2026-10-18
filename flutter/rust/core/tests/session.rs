use cookdex_core::{
    adapters::AppPaths,
    session::Session,
    storage::{self, Book},
};
use rusqlite::Connection;
use std::{
    path::PathBuf,
    sync::{Arc, Barrier},
};

struct Sandbox(PathBuf);
impl Sandbox {
    fn new() -> Self {
        let root = std::env::temp_dir().join(format!("cookdex-session-{}", uuid::Uuid::new_v4()));
        std::fs::create_dir(&root).unwrap();
        Self(root)
    }
}
impl AppPaths for Sandbox {
    fn private_root(&self) -> Result<PathBuf, String> {
        Ok(self.0.clone())
    }
}
impl Drop for Sandbox {
    fn drop(&mut self) {
        std::fs::remove_dir_all(&self.0).unwrap();
    }
}
fn fixture() -> Book {
    serde_json::from_str(include_str!("native-fixture.json")).unwrap()
}

#[test]
fn fresh_namespace_ignores_legacy_files_and_reopens_own_identity() {
    let sandbox = Sandbox::new();
    let old = sandbox.0.join("recipe-book.sqlite3");
    let sentinel = b"old database must never be read or modified";
    std::fs::write(&old, sentinel).unwrap();
    std::fs::write(
        sandbox.0.join("smart-import-settings.json"),
        b"not valid JSON",
    )
    .unwrap();
    let session = Session::open(&sandbox).unwrap();
    assert_eq!(session.load().unwrap().book, Book::default());
    let id = session.device_id().unwrap();
    assert!(!id.is_empty());
    session.save(0, &fixture(), "fixture").unwrap();
    session.foreground(true).unwrap(); // disabled, no socket binding
    session.foreground(false).unwrap();
    drop(session);
    let session = Session::open(&sandbox).unwrap();
    assert_eq!(session.device_id().unwrap(), id);
    assert_eq!(session.load().unwrap().book, fixture());
    assert_eq!(std::fs::read(old).unwrap(), sentinel);
    let other = Sandbox::new();
    let other_session = Session::open(&other).unwrap();
    assert_ne!(other_session.device_id().unwrap(), id);
    assert_eq!(other_session.load().unwrap().generation, 0);
}

#[test]
fn competing_sessions_commit_one_write_and_reject_the_stale_one() {
    let sandbox = Sandbox::new();
    let a = Session::open(&sandbox).unwrap();
    let b = Session::open(&sandbox).unwrap();
    let barrier = Arc::new(Barrier::new(2));
    let workers: Vec<_> = [a, b]
        .into_iter()
        .enumerate()
        .map(|(i, session)| {
            let barrier = barrier.clone();
            std::thread::spawn(move || {
                let mut book = fixture();
                book.recipes[0]["title"] = format!("Writer {i}").into();
                barrier.wait();
                session.save(0, &book, "synthetic")
            })
        })
        .collect();
    let results: Vec<_> = workers.into_iter().map(|w| w.join().unwrap()).collect();
    assert_eq!(results.iter().filter(|r| matches!(r, Ok(1))).count(), 1);
    assert_eq!(
        results
            .iter()
            .filter(|r| r.as_ref().is_err_and(|e| e.contains("STALE_WRITE")))
            .count(),
        1
    );
    let session = Session::open(&sandbox).unwrap();
    assert_eq!(session.load().unwrap().generation, 1);
    let db = Connection::open(sandbox.0.join("flutter-v1/cookdex.sqlite3")).unwrap();
    assert_eq!(
        db.query_row("SELECT count(*) FROM history", [], |r| r.get::<_, i64>(0))
            .unwrap(),
        1
    );
}

#[test]
fn foreign_or_unmarked_databases_are_rejected_without_adoption() {
    for version in [0, 1, 2, 99] {
        let sandbox = Sandbox::new();
        let path = sandbox.0.join("foreign.sqlite3");
        let db = Connection::open(&path).unwrap();
        db.execute_batch(&format!("CREATE TABLE legacy (body TEXT); INSERT INTO legacy VALUES ('sentinel'); PRAGMA user_version={version};")).unwrap();
        drop(db);
        let before = std::fs::read(&path).unwrap();
        assert!(storage::open(&path).is_err());
        assert_eq!(std::fs::read(path).unwrap(), before);
    }
}

#[test]
fn relative_paths_fail_before_any_store_is_created() {
    struct Relative;
    impl AppPaths for Relative {
        fn private_root(&self) -> Result<PathBuf, String> {
            Ok("relative-root".into())
        }
    }
    assert!(Session::open(&Relative).is_err());
}
