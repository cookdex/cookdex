use cookdex_core::{
    adapters::AppPaths,
    backup,
    recipe::{Recipe, RecipeId},
    services::{Error, Operation, Service},
    storage, sync_store,
};
use std::{net::TcpListener, path::PathBuf};
struct Peer {
    service: Service,
    root: PathBuf,
    port: u16,
    // Fields drop in declaration order: close the service before its directory.
    _cleanup: TemporaryPeer,
}
struct TemporaryPeer(PathBuf);
impl Drop for TemporaryPeer {
    fn drop(&mut self) {
        if self.0.exists() {
            let result = std::fs::remove_dir_all(&self.0);
            if !std::thread::panicking() {
                result.expect("synthetic peer directory cleanup failed");
            }
        }
    }
}
impl AppPaths for PathRoot {
    fn private_root(&self) -> Result<PathBuf, String> {
        Ok(self.0.clone())
    }
}
struct PathRoot(PathBuf);
impl Peer {
    fn new(name: &str) -> Self {
        let root = std::env::temp_dir().join(format!("cookdex-c9-{}", uuid::Uuid::new_v4()));
        let cleanup = TemporaryPeer(root.clone());
        let listener = TcpListener::bind("127.0.0.1:0").unwrap();
        let port = listener.local_addr().unwrap().port();
        drop(listener);
        let service = Service::open_with_port(&PathRoot(root.clone()), port).unwrap();
        service.sync_pairing(true);
        service.sync_configure(true, name.into()).unwrap();
        service.sync_host_active(true).unwrap();
        Self {
            service,
            root,
            port,
            _cleanup: cleanup,
        }
    }
    fn pair(&self, other: &Self) {
        self.service
            .sync_pair(other.service.sync_invitation("127.0.0.1".into()).unwrap())
            .unwrap();
        self.service.sync_now().unwrap();
    }
    fn seed(&self) -> RecipeId {
        let recipes = fixture();
        let preview = self
            .service
            .preview_restore(&backup::write(&recipes).unwrap(), &op())
            .unwrap();
        self.service.restore(&preview, &op()).unwrap();
        recipes[0].id.clone()
    }
    fn recipe(&self, id: &RecipeId) -> Recipe {
        self.service.detail(id).unwrap().unwrap()
    }
    fn edit(&self, id: &RecipeId, note: &str) {
        let base = self.recipe(id);
        let mut fields = base.content.clone();
        fields.notes = note.into();
        self.service
            .save(
                self.service.snapshot().unwrap().generation,
                Some(base),
                fields,
                &op(),
            )
            .unwrap();
    }
}
#[test]
fn dropping_peer_removes_its_synthetic_store() {
    let peer = Peer::new("Cleanup fixture");
    let root = peer.root.clone();
    assert!(root.is_dir());
    drop(peer);
    assert!(!root.exists());
}
fn op() -> Operation {
    Operation::default()
}
fn fixture() -> Vec<Recipe> {
    let v: serde_json::Value =
        serde_json::from_str(include_str!("../../../../tests/fixtures/corpus.json")).unwrap();
    serde_json::from_value(v["recipes"].clone()).unwrap()
}

#[test]
fn three_live_peers_direct_and_relay_conflicts_cleanup_and_revocation() {
    let phone = Peer::new("Phone");
    let tablet = Peer::new("Tablet");
    let pc = Peer::new("PC");
    let id = phone.seed();
    // Phone/tablet pair and exchange with no PC route. Newly paired receives all.
    tablet.pair(&phone);
    assert_eq!(
        tablet.service.snapshot().unwrap().summaries.len(),
        fixture().len()
    );
    pc.pair(&tablet);
    phone.edit(&id, "Phone offline edit");
    phone.service.sync_now().unwrap();
    tablet.service.sync_now().unwrap();
    assert_eq!(pc.recipe(&id).content.notes, "Phone offline edit");
    let stale_heads;
    phone.edit(&id, "Phone conflict");
    pc.edit(&id, "PC conflict");
    tablet.service.sync_now().unwrap();
    let conflict = tablet
        .service
        .snapshot()
        .unwrap()
        .conflicts
        .into_iter()
        .find(|c| c.recipe_id == id)
        .unwrap();
    stale_heads = conflict
        .versions
        .iter()
        .map(|v| v.id.clone())
        .collect::<Vec<_>>();
    assert!(tablet.service.backup(&op()).is_err());
    let preview = tablet.service.preview_cleanup().unwrap();
    assert_eq!(preview.skipped_conflicts, 1);
    let before = tablet.recipe(&id);
    tablet.service.cleanup(&preview, &op()).unwrap();
    assert_eq!(tablet.recipe(&id), before);
    tablet
        .service
        .resolve(&id.0, &stale_heads, "keep-all")
        .unwrap();
    assert_eq!(
        tablet
            .service
            .resolve(&id.0, &stale_heads, "keep-all")
            .unwrap_err(),
        Error::ConflictChanged
    );
    tablet.service.sync_now().unwrap();
    phone.service.sync_now().unwrap();
    assert!(phone.service.snapshot().unwrap().conflicts.is_empty());
    assert!(pc.service.snapshot().unwrap().conflicts.is_empty());
    let generation = phone.service.snapshot().unwrap().generation;
    phone.service.delete(generation, &id, &op()).unwrap();
    pc.edit(&id, "Concurrent with deletion");
    tablet.service.sync_now().unwrap();
    let conflict = tablet
        .service
        .snapshot()
        .unwrap()
        .conflicts
        .into_iter()
        .find(|c| c.recipe_id == id)
        .unwrap();
    let deletion = conflict
        .versions
        .iter()
        .find(|v| v.recipe.is_none())
        .unwrap();
    tablet
        .service
        .resolve(
            &id.0,
            &conflict
                .versions
                .iter()
                .map(|v| v.id.clone())
                .collect::<Vec<_>>(),
            &deletion.id,
        )
        .unwrap();
    tablet.service.sync_now().unwrap();
    phone.service.sync_now().unwrap();
    assert!(phone.service.detail(&id).unwrap().is_none());
    assert!(pc.service.detail(&id).unwrap().is_none());
    let tablet_id = tablet.service.sync_status().unwrap()["deviceId"]
        .as_str()
        .unwrap()
        .to_string();
    phone.service.sync_forget(&tablet_id).unwrap();
    tablet.service.sync_now().unwrap();
    let reports = tablet.service.sync_status().unwrap();
    assert!(
        reports["reports"]
            .as_array()
            .unwrap()
            .iter()
            .any(|r| r["name"] == "Phone" && r["status"] == "error")
    );
    assert!(
        phone.service.sync_status().unwrap()["peers"]
            .as_array()
            .unwrap()
            .is_empty()
    );
    assert_ne!(phone.port, 47831);
    assert!(phone.root.exists());
}

#[test]
fn clock_skew_hours_cannot_choose_a_sync_winner_and_deleted_ancestry_survives() {
    let mut a = storage::open(std::path::Path::new(":memory:")).unwrap();
    let mut b = storage::open(std::path::Path::new(":memory:")).unwrap();
    let mut c = storage::open(std::path::Path::new(":memory:")).unwrap();
    let mut book = storage::Book {
        recipes: fixture()
            .iter()
            .map(|r| serde_json::to_value(r).unwrap())
            .collect(),
        ..Default::default()
    };
    storage::save(&mut a, 0, &book, "2026-10-09T01:00:00Z").unwrap();
    sync_store::merge(
        &mut b,
        sync_store::export(&a).unwrap(),
        "2026-10-08T22:00:00Z",
    )
    .unwrap();
    sync_store::merge(
        &mut c,
        sync_store::export(&a).unwrap(),
        "2026-10-10T03:00:00Z",
    )
    .unwrap();
    let id = book.recipes[0]["id"].as_str().unwrap().to_string();
    book.recipes[0]["notes"] = serde_json::json!("future clock");
    book.recipes[0]["updatedAt"] = serde_json::json!("2026-10-10T03:00:00Z");
    storage::save(&mut a, 1, &book, "2026-10-10T03:00:00Z").unwrap();
    let mut other = storage::load(&mut b).unwrap();
    let row = other
        .book
        .recipes
        .iter_mut()
        .find(|r| r["id"] == id)
        .unwrap();
    row["notes"] = serde_json::json!("past clock");
    row["updatedAt"] = serde_json::json!("2026-10-08T22:00:00Z");
    storage::save(
        &mut b,
        other.generation,
        &other.book,
        "2026-10-08T22:00:00Z",
    )
    .unwrap();
    sync_store::merge(
        &mut a,
        sync_store::export(&b).unwrap(),
        "2026-10-09T00:00:00Z",
    )
    .unwrap();
    let conflict = sync_store::conflicts(&a).unwrap();
    let heads = conflict[0]["versions"]
        .as_array()
        .unwrap()
        .iter()
        .map(|v| v["id"].as_str().unwrap().to_string())
        .collect::<Vec<_>>();
    assert_eq!(heads.len(), 2);
    sync_store::resolve(&mut a, &id, &heads, &heads[0], "2026-10-09T00:00:00Z").unwrap();
    let mut s = storage::load(&mut a).unwrap();
    s.book.recipes.retain(|r| r["id"] != id);
    s.book
        .deleted_recipes
        .push(serde_json::json!({"id":id,"deletedAt":"2026-10-08T21:00:00Z"}));
    storage::save(&mut a, s.generation, &s.book, "2026-10-08T21:00:00Z").unwrap();
    sync_store::merge(
        &mut a,
        sync_store::export(&c).unwrap(),
        "2026-10-11T00:00:00Z",
    )
    .unwrap();
    assert!(
        !storage::load(&mut a)
            .unwrap()
            .book
            .recipes
            .iter()
            .any(|r| r["id"] == id)
    );
}

#[test]
fn cleanup_preserves_exact_quantities_favorites_ids_and_rejects_changed_preview() {
    let p = Peer::new("Cleanup");
    let id = p.seed();
    let original = p.recipe(&id);
    let preview = p.service.preview_cleanup().unwrap();
    p.edit(&id, "Changed after preview");
    assert_eq!(
        p.service.cleanup(&preview, &op()).unwrap_err(),
        Error::StaleWrite
    );
    let preview = p.service.preview_cleanup().unwrap();
    p.service.cleanup(&preview, &op()).unwrap();
    let after = p.recipe(&id);
    assert_eq!(after.id, original.id);
    assert_eq!(after.created_at, original.created_at);
    assert_eq!(after.favorite, original.favorite);
    assert_eq!(
        after
            .content
            .ingredients
            .iter()
            .map(|i| &i.amount)
            .collect::<Vec<_>>(),
        original
            .content
            .ingredients
            .iter()
            .map(|i| &i.amount)
            .collect::<Vec<_>>()
    );
    assert_eq!(p.service.preview_cleanup().unwrap().changed, 0);
}

#[test]
fn explicit_cleanup_is_a_normal_successor_and_reaches_another_peer() {
    let a = Peer::new("Cleanup source");
    let b = Peer::new("Cleanup receiver");
    let mut recipes = fixture();
    let id = recipes[0].id.clone();
    recipes[0].content.tags = vec!["Dinner".into(), "DINNER".into()];
    recipes[0].content.total_time = "PT1H30M".into();
    recipes[0].content.ingredients[0].unit = "Tbs.".into();
    let archive = backup::write(&recipes).unwrap();
    a.service
        .restore(&a.service.preview_restore(&archive, &op()).unwrap(), &op())
        .unwrap();
    b.pair(&a);
    let original = a.recipe(&id);
    a.service
        .cleanup(&a.service.preview_cleanup().unwrap(), &op())
        .unwrap();
    let cleaned = a.recipe(&id);
    assert_eq!(cleaned.revision, original.revision + 1);
    assert_eq!(cleaned.content.tags, vec!["Dinner", "DINNER"]);
    assert_eq!(cleaned.content.total_time, "1 hr 30 min");
    assert_eq!(cleaned.content.ingredients[0].unit, "tbsp");
    assert_eq!(
        cleaned.content.ingredients[0].amount,
        original.content.ingredients[0].amount
    );
    a.service.sync_now().unwrap();
    assert_eq!(b.recipe(&id), cleaned);
}

#[test]
fn oversized_history_count_and_transport_bytes_fail_without_mutation_and_local_state_never_syncs() {
    let mut a = storage::open(std::path::Path::new(":memory:")).unwrap();
    let mut b = storage::open(std::path::Path::new(":memory:")).unwrap();
    let book = storage::Book {
        recipes: fixture()
            .iter()
            .map(|r| serde_json::to_value(r).unwrap())
            .collect(),
        ..Default::default()
    };
    storage::save(&mut a, 0, &book, "2026-10-09T00:00:00Z").unwrap();
    for name in [
        "editorDraft",
        "cookPosition",
        "geminiKey",
        "syncConfig",
        "uiPreferences",
    ] {
        a.execute(
            "INSERT INTO local(key,body) VALUES(?1,?2)",
            rusqlite::params![name, r#"{"fixture":"local only"}"#],
        )
        .unwrap();
    }
    let packet = sync_store::export(&a).unwrap();
    let oversized = sync_store::Packet {
        version: sync_store::VERSION,
        events: vec![packet.events[0].clone(); 100001],
    };
    assert!(
        sync_store::merge(&mut b, oversized, "2026-10-09T00:00:00Z")
            .unwrap_err()
            .contains("oversized")
    );
    assert_eq!(storage::load(&mut b).unwrap().generation, 0);
    let mut large = packet.events[0].clone();
    large.recipe.as_mut().unwrap()["notes"] = serde_json::json!("x".repeat(96 * 1024 * 1024));
    assert!(
        sync_store::merge(
            &mut b,
            sync_store::Packet {
                version: sync_store::VERSION,
                events: vec![large]
            },
            "2026-10-09T00:00:00Z"
        )
        .unwrap_err()
        .contains("oversized")
    );
    assert_eq!(storage::load(&mut b).unwrap().generation, 0);
    sync_store::merge(&mut b, packet, "2026-10-09T00:00:00Z").unwrap();
    for name in [
        "editorDraft",
        "cookPosition",
        "geminiKey",
        "syncConfig",
        "uiPreferences",
    ] {
        assert_eq!(
            b.query_row("SELECT count(*) FROM local WHERE key=?1", [name], |r| r
                .get::<_, i64>(0))
                .unwrap(),
            0
        );
    }
}

#[test]
fn incoming_commit_notifies_subscribers_and_leaves_third_device_pending() {
    let a = Peer::new("A");
    let b = Peer::new("B");
    let c = Peer::new("C");
    let id = a.seed();
    b.pair(&a);
    c.pair(&a);
    let sub = a.service.subscribe().unwrap();
    b.edit(&id, "incoming change for third device");
    b.service.sync_now().unwrap();
    let change = sub
        .receiver
        .recv_timeout(std::time::Duration::from_secs(2))
        .unwrap();
    assert!(change.generation > sub.snapshot.generation);
    assert!(change.changed.contains(&id));
    let status = a.service.sync_status().unwrap();
    let peers = status["peers"].as_array().unwrap();
    assert!(peers.iter().any(|p| p["caughtUp"] == false));
    assert!(peers.iter().any(|p| p["caughtUp"] == true));
}
