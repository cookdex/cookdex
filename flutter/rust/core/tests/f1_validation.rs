use cookdex_core::{
    adapters::AppPaths,
    backup,
    recipe::Recipe,
    services::{Operation, Service},
    storage, sync_store,
};
use rusqlite::{Connection, params};
use serde_json::{Value, json};
use std::path::{Path, PathBuf};

fn fixture() -> storage::Book {
    serde_json::from_str(include_str!("native-fixture.json")).unwrap()
}
fn memory_db() -> Connection {
    storage::open(Path::new(":memory:")).unwrap()
}
fn state(db: &Connection) -> Vec<Vec<String>> {
    [
        "SELECT body FROM recipes ORDER BY id",
        "SELECT body FROM history ORDER BY id",
        "SELECT body FROM local ORDER BY key",
        "SELECT revision_id FROM heads ORDER BY recipe_id",
        "SELECT CAST(generation AS TEXT) FROM state",
    ]
    .iter()
    .map(|sql| {
        db.prepare(sql)
            .unwrap()
            .query_map([], |r| r.get(0))
            .unwrap()
            .collect::<Result<Vec<String>, _>>()
            .unwrap()
    })
    .collect()
}

#[test]
fn sync_canonical_rejections_leave_every_table_unchanged() {
    let mut source = memory_db();
    storage::save(&mut source, 0, &fixture(), "seed").unwrap();
    let packet = sync_store::export(&source).unwrap();
    let mutations: Vec<(&str, Value)> = vec![
        ("/createdAt", json!("yesterday")),
        ("/updatedAt", json!("2026-99-99T00:00:00Z")),
        ("/unexpected", json!(true)),
        ("/ingredients/0/unexpected", json!(1)),
        ("/ingredients/0/amount/unexpected", json!(1)),
        ("/ingredients/0/amount/denominator", json!(0)),
        ("/ingredients/0/amount/numerator", json!(-1)),
        (
            "/ingredients/0/amount/numerator",
            json!(9007199254740992u64),
        ),
        ("/title", json!("x".repeat(161))),
        ("/notes", json!("x".repeat(20001))),
        ("/description", json!("x".repeat(2001))),
        ("/servings", json!("x".repeat(81))),
        ("/ingredients/0/name", json!("x".repeat(2001))),
        ("/steps/0", json!("x".repeat(30001))),
        ("/tags", json!(["x".repeat(301)])),
    ];
    for (pointer, value) in mutations {
        let mut destination = memory_db();
        let mut local = fixture();
        local.recipes[0]["id"] = json!("local-recipe");
        storage::save(&mut destination, 0, &local, "local").unwrap();
        let before = state(&destination);
        let mut invalid = packet.clone();
        let recipe = invalid.events[0].recipe.as_mut().unwrap();
        let (parent, key) = pointer.rsplit_once('/').unwrap();
        if let Some(object) = recipe.pointer_mut(parent).and_then(Value::as_object_mut) {
            object.insert(key.into(), value);
        } else {
            *recipe.pointer_mut(pointer).unwrap() = value;
        }
        let invalid_book = storage::Book {
            recipes: vec![recipe.clone()],
            ..Default::default()
        };
        assert!(
            storage::save(&mut destination, 1, &invalid_book, "invalid local write").is_err(),
            "{pointer}"
        );
        assert_eq!(state(&destination), before);
        // An otherwise-valid new event in the same packet must also roll back.
        let mut good = packet.events[0].clone();
        good.id = "good-event".into();
        good.recipe_id = "good-recipe".into();
        good.recipe.as_mut().unwrap()["id"] = json!("good-recipe");
        invalid.events.insert(0, good);
        let error = sync_store::merge(&mut destination, invalid, "sync").unwrap_err();
        assert_eq!(error, sync_store::RECIPE_ERROR, "{pointer}");
        assert_eq!(state(&destination), before, "{pointer}");
    }
    let mut invalid_range = packet;
    let recipe = invalid_range.events[0].recipe.as_mut().unwrap();
    recipe["schemaVersion"] = json!(2);
    recipe["ingredients"][0]["amount"] = json!({"kind":"range",
        "lower":{"numerator":3,"denominator":1}, "upper":{"numerator":1,"denominator":1}});
    assert_eq!(
        sync_store::merge(&mut memory_db(), invalid_range, "sync").unwrap_err(),
        sync_store::RECIPE_ERROR
    );
}

#[test]
fn valid_schema_one_payload_and_digest_remain_exact() {
    let mut source = memory_db();
    let mut book = fixture();
    book.recipes[0]["ingredients"][0]["amount"] =
        json!({"kind":"number","numerator":2,"denominator":6});
    storage::save(&mut source, 0, &book, "seed").unwrap();
    let packet = sync_store::export(&source).unwrap();
    let manifest = sync_store::manifest(&packet).unwrap();
    let mut destination = memory_db();
    sync_store::merge(&mut destination, packet.clone(), "sync").unwrap();
    let exported = sync_store::export(&destination).unwrap();
    assert_eq!(exported.events, packet.events);
    assert_eq!(sync_store::manifest(&exported).unwrap(), manifest);
    assert_eq!(storage::load(&mut destination).unwrap().book, book);
}

struct Root(PathBuf);
impl Root {
    fn new() -> Self {
        Self(std::env::temp_dir().join(format!("cookdex-f1-{}", uuid::Uuid::new_v4())))
    }
}
impl AppPaths for Root {
    fn private_root(&self) -> Result<PathBuf, String> {
        Ok(self.0.clone())
    }
}
impl Drop for Root {
    fn drop(&mut self) {
        if self.0.exists() {
            std::fs::remove_dir_all(&self.0).unwrap();
        }
    }
}
fn op() -> Operation {
    Operation::default()
}
fn connection(root: &Root) -> Connection {
    storage::open(&root.0.join("flutter-v1/cookdex.sqlite3")).unwrap()
}

#[test]
fn detail_matches_canonical_library_for_each_kind_of_unreadable_recipe() {
    for damage in ["json", "identity", "canonical", "head", "conflict"] {
        let root = Root::new();
        let service = Service::open(&root).unwrap();
        let (recipes, _) = seed(&service);
        let mut db = connection(&root);
        let id = &recipes[0].id;
        let original: String = db
            .query_row("SELECT body FROM recipes WHERE id=?1", [&id.0], |r| {
                r.get(0)
            })
            .unwrap();
        let mut bad: Value = serde_json::from_str(&original).unwrap();
        bad["updatedAt"] = json!("invalid");
        match damage {
            "json" => {
                db.execute(
                    "UPDATE recipes SET body='invalid json' WHERE id=?1",
                    [&id.0],
                )
                .unwrap();
            }
            "identity" => {
                bad["updatedAt"] = json!(recipes[0].updated_at);
                bad["id"] = json!("different-id");
                db.execute(
                    "UPDATE recipes SET body=?2 WHERE id=?1",
                    params![id.0, bad.to_string()],
                )
                .unwrap();
            }
            "canonical" => {
                db.execute(
                    "UPDATE recipes SET body=?2 WHERE id=?1",
                    params![id.0, bad.to_string()],
                )
                .unwrap();
            }
            "head" => {
                let (revision, body): (String, String) = db.query_row("SELECT h.id,h.body FROM history h JOIN heads p ON p.revision_id=h.id WHERE p.recipe_id=?1", [&id.0], |r| Ok((r.get(0)?, r.get(1)?))).unwrap();
                let mut event: Value = serde_json::from_str(&body).unwrap();
                event["recipe"] = bad;
                db.execute(
                    "UPDATE history SET body=?2 WHERE id=?1",
                    params![revision, event.to_string()],
                )
                .unwrap();
            }
            "conflict" => {
                db.execute(
                    "INSERT OR REPLACE INTO local VALUES('syncConflicts',?1)",
                    [json!([{"recipeId":id.0,"versions":[{"recipe":bad}]}]).to_string()],
                )
                .unwrap();
            }
            _ => unreachable!(),
        }
        let before = state(&db);
        assert!(service.detail(id).unwrap().is_none(), "{damage}");
        let healthy = service.detail(&recipes[1].id).unwrap().unwrap();
        assert_eq!(healthy.content, recipes[1].content, "{damage}");
        assert_eq!(
            state(&db),
            before,
            "reads must preserve recovery data: {damage}"
        );
        let snapshot = storage::load(&mut db).unwrap();
        assert_eq!(snapshot.set_aside, vec![id.0.clone()]);
        assert_eq!(snapshot.book.recipes.len(), 1);
    }
}

#[test]
fn detail_tracks_edits_delete_restore_recovery_and_incoming_conflict() {
    let root = Root::new();
    let service = Service::open(&root).unwrap();
    let (recipes, bytes) = seed(&service);
    let id = &recipes[0].id;
    let base = service.detail(id).unwrap().unwrap();
    let mut fields = base.content.clone();
    fields.notes = "Edited locally".into();
    let edited = service
        .save(
            service.snapshot().unwrap().generation,
            Some(base),
            fields.clone(),
            &op(),
        )
        .unwrap();
    assert_eq!(service.detail(id).unwrap().unwrap().content, fields);
    let deleted = service.delete(edited.generation, id, &op()).unwrap();
    assert!(service.detail(id).unwrap().is_none());
    service.recover(deleted.generation, &op()).unwrap();
    assert_eq!(service.detail(id).unwrap().unwrap().content, fields);
    let mut peer = memory_db();
    storage::save(
        &mut peer,
        0,
        &storage::Book {
            recipes: recipes
                .iter()
                .map(|r| serde_json::from_slice(&r.to_json().unwrap()).unwrap())
                .collect(),
            ..Default::default()
        },
        "peer",
    )
    .unwrap();
    let packet = sync_store::export(&peer).unwrap();
    sync_store::merge(&mut connection(&root), packet, "incoming").unwrap();
    let snapshot = service.snapshot().unwrap();
    assert!(!snapshot.conflicts.is_empty());
    let expected = storage::load(&mut connection(&root))
        .unwrap()
        .book
        .recipes
        .into_iter()
        .find(|r| r["id"] == id.0)
        .unwrap();
    assert_eq!(
        service.detail(id).unwrap().unwrap(),
        Recipe::from_json(&serde_json::to_vec(&expected).unwrap()).unwrap()
    );
    service
        .restore(&service.preview_restore(&bytes, &op()).unwrap(), &op())
        .unwrap();
    assert!(service.detail(id).unwrap().is_some());
}

#[test]
fn detail_rejects_target_envelope_and_ancestry_damage_without_writes() {
    for damage in [
        "kind",
        "event-id",
        "recipe-id",
        "deleted-at",
        "stub",
        "missing-parent",
        "cycle",
    ] {
        let root = Root::new();
        let service = Service::open(&root).unwrap();
        let (recipes, _) = seed(&service);
        let mut db = connection(&root);
        let id = &recipes[0].id;
        let (revision, body): (String, String) = db.query_row(
            "SELECT h.id,h.body FROM heads p JOIN history h ON h.id=p.revision_id WHERE p.recipe_id=?1",
            [&id.0], |r| Ok((r.get(0)?, r.get(1)?)),
        ).unwrap();
        let mut event: Value = serde_json::from_str(&body).unwrap();
        match damage {
            "kind" => event["kind"] = json!("unknown"),
            "event-id" => event["id"] = json!("wrong"),
            "recipe-id" => event["recipeId"] = json!("wrong"),
            "deleted-at" => event["deletedAt"] = json!("unexpected"),
            "stub" => {
                event["recipe"] = Value::Null;
                event["recipeDigest"] = json!("a".repeat(64));
            }
            "missing-parent" => event["parents"] = json!(["missing"]),
            "cycle" => event["parents"] = json!([revision]),
            _ => unreachable!(),
        }
        db.execute(
            "UPDATE history SET body=?2 WHERE id=?1",
            params![revision, event.to_string()],
        )
        .unwrap();
        let before = state(&db);
        assert!(
            storage::load(&mut db).is_err(),
            "old collection validation: {damage}"
        );
        assert!(service.detail(id).is_err(), "scoped validation: {damage}");
        assert_eq!(state(&db), before);
        // Unrelated corrupt projection must not disable validation of this ID.
        db.execute(
            "UPDATE recipes SET body='broken' WHERE id=?1",
            [&recipes[1].id.0],
        )
        .unwrap();
        assert!(
            service.detail(id).is_err(),
            "independent target guarantee: {damage}"
        );
    }
}

#[test]
fn target_set_aside_precedes_history_envelope_error() {
    for conflict in [false, true] {
        let root = Root::new();
        let service = Service::open(&root).unwrap();
        let (recipes, _) = seed(&service);
        let db = connection(&root);
        let id = &recipes[0].id;
        let (revision, body): (String, String) = db.query_row(
            "SELECT h.id,h.body FROM heads p JOIN history h ON h.id=p.revision_id WHERE p.recipe_id=?1",
            [&id.0], |r| Ok((r.get(0)?, r.get(1)?)),
        ).unwrap();
        let mut event: Value = serde_json::from_str(&body).unwrap();
        let mut bad = event["recipe"].clone();
        bad["updatedAt"] = json!("invalid");
        event["id"] = json!("wrong-envelope");
        if conflict {
            db.execute(
                "INSERT OR REPLACE INTO local VALUES('syncConflicts',?1)",
                [json!([{"recipeId":id.0,"versions":[{"recipe":bad}]}]).to_string()],
            )
            .unwrap();
        } else {
            event["recipe"] = bad;
        }
        db.execute(
            "UPDATE history SET body=?2 WHERE id=?1",
            params![revision, event.to_string()],
        )
        .unwrap();
        assert!(service.detail(id).unwrap().is_none());
    }
}

#[test]
fn detail_conflict_filter_preserves_stored_duplicate_identity_semantics() {
    for target_last in [false, true] {
        let root = Root::new();
        let service = Service::open(&root).unwrap();
        let (recipes, _) = seed(&service);
        let mut db = connection(&root);
        let id = &recipes[0].id;
        let mut bad: Value = serde_json::from_slice(&recipes[0].to_json().unwrap()).unwrap();
        bad["updatedAt"] = json!("invalid");
        let (first, last) = if target_last {
            ("other", id.0.as_str())
        } else {
            (id.0.as_str(), "other")
        };
        let body = format!(
            "[{{\"recipeId\":{},\"recipeId\":{},\"versions\":[{{\"recipe\":{}}}]}}]",
            json!(first),
            json!(last),
            bad
        );
        db.execute(
            "INSERT OR REPLACE INTO local VALUES('syncConflicts',?1)",
            [body],
        )
        .unwrap();
        let snapshot = storage::load(&mut db).unwrap();
        assert_eq!(
            snapshot.book.recipes.iter().any(|r| r["id"] == id.0),
            !target_last
        );
        assert_eq!(service.detail(id).unwrap().is_some(), !target_last);
    }
}
fn seed(service: &Service) -> (Vec<Recipe>, Vec<u8>) {
    let mut first = fixture().recipes.remove(0);
    let mut second = first.clone();
    second["id"] = json!("healthy-recipe");
    second["title"] = json!("Healthy");
    first["title"] = json!("Recover me");
    let recipes: Vec<_> = [first, second]
        .iter()
        .map(|r| Recipe::from_json(&serde_json::to_vec(r).unwrap()).unwrap())
        .collect();
    let bytes = backup::write(&recipes).unwrap();
    let snapshot = service
        .restore(&service.preview_restore(&bytes, &op()).unwrap(), &op())
        .unwrap();
    service
        .favorite(snapshot.generation, &recipes[1].id, true, &op())
        .unwrap();
    (recipes, bytes)
}
fn corrupt(root: &Root, id: &str, malformed: bool) -> (String, String) {
    let db = connection(root);
    let (body, revision): (String, String) = db
        .query_row(
            "SELECT body,revision_id FROM recipes WHERE id=?1",
            [id],
            |r| Ok((r.get(0)?, r.get(1)?)),
        )
        .unwrap();
    let mut recipe: Value = serde_json::from_str(&body).unwrap();
    recipe["updatedAt"] = json!("invalid date");
    let mut event: Value = serde_json::from_str(
        &db.query_row::<String, _, _>("SELECT body FROM history WHERE id=?1", [&revision], |r| {
            r.get(0)
        })
        .unwrap(),
    )
    .unwrap();
    event["recipe"] = recipe.clone();
    let body = if malformed {
        "not json".into()
    } else {
        recipe.to_string()
    };
    db.execute("UPDATE recipes SET body=?2 WHERE id=?1", params![id, body])
        .unwrap();
    db.execute(
        "UPDATE history SET body=?2 WHERE id=?1",
        params![revision, event.to_string()],
    )
    .unwrap();
    (body, event.to_string())
}

#[test]
fn corrupt_rows_do_not_block_loading_editing_backup_or_zip_restore() {
    for malformed in [false, true] {
        let root = Root::new();
        let service = Service::open(&root).unwrap();
        let (recipes, bytes) = seed(&service);
        let (body, history) = corrupt(&root, &recipes[0].id.0, malformed);
        let previous = storage::previous(&connection(&root)).unwrap();
        let snapshot = service.snapshot().unwrap();
        assert_eq!(snapshot.set_aside_count, 1);
        assert_eq!(snapshot.summaries.len(), 1);
        assert!(service.detail(&recipes[0].id).unwrap().is_none());
        assert!(
            sync_store::export(&connection(&root))
                .unwrap_err()
                .contains("Sync is paused")
        );
        let mut healthy = service.detail(&recipes[1].id).unwrap().unwrap();
        healthy.content.notes = "Still editable".into();
        let snapshot = service
            .save(
                snapshot.generation,
                service.detail(&recipes[1].id).unwrap(),
                healthy.content,
                &op(),
            )
            .unwrap();
        assert_eq!(snapshot.set_aside_count, 1);
        let db = connection(&root);
        assert_eq!(storage::previous(&db).unwrap(), previous);
        assert_eq!(
            db.query_row::<String, _, _>(
                "SELECT body FROM recipes WHERE id=?1",
                [&recipes[0].id.0],
                |r| r.get(0)
            )
            .unwrap(),
            body
        );
        assert_eq!(
            db.query_row::<i64, _, _>(
                "SELECT count(*) FROM history WHERE body=?1",
                [&history],
                |r| r.get(0)
            )
            .unwrap(),
            1
        );
        drop(db);
        let report = service.backup_report(&op()).unwrap();
        assert_eq!(report.omitted, 1);
        assert_eq!(backup::read(&report.bytes).unwrap().len(), 1);
        let preview = service.preview_restore(&bytes, &op()).unwrap();
        let restored = service.restore(&preview, &op()).unwrap();
        assert_eq!(restored.set_aside_count, 0);
        assert_eq!(restored.summaries.len(), 2);
        assert_eq!(service.detail(&recipes[0].id).unwrap().unwrap(), recipes[0]);
        let packet = sync_store::export(&connection(&root)).unwrap();
        sync_store::validate_packet(&packet).unwrap();
        assert!(packet.events.iter().any(|e| e.recipe_digest.is_some()));
        assert_eq!(
            connection(&root)
                .query_row::<i64, _, _>(
                    "SELECT count(*) FROM history WHERE body=?1",
                    [&history],
                    |r| r.get(0)
                )
                .unwrap(),
            1
        );
        let mut peer = memory_db();
        sync_store::merge(&mut peer, packet, "sync").unwrap();
        assert_eq!(storage::load(&mut peer).unwrap().book.recipes.len(), 2);
    }
}

#[test]
fn previous_save_recovery_and_confirmed_discard_work_with_bad_storage() {
    for discard in [false, true] {
        let root = Root::new();
        let service = Service::open(&root).unwrap();
        let (recipes, _) = seed(&service);
        corrupt(&root, &recipes[0].id.0, true);
        let snapshot = service.snapshot().unwrap();
        if discard {
            assert!(
                service
                    .discard_set_aside(snapshot.generation - 1, &op())
                    .is_err()
            );
            assert_eq!(service.snapshot().unwrap().set_aside_count, 1);
            let cancelled = op();
            cancelled.cancel();
            assert!(
                service
                    .discard_set_aside(snapshot.generation, &cancelled)
                    .is_err()
            );
            let after = service
                .discard_set_aside(snapshot.generation, &op())
                .unwrap();
            assert_eq!(after.set_aside_count, 0);
            assert_eq!(after.summaries.len(), 1);
        } else {
            let after = service.recover(snapshot.generation, &op()).unwrap();
            assert_eq!(after.set_aside_count, 0);
            assert_eq!(after.summaries.len(), 2);
            assert_eq!(
                service.detail(&recipes[0].id).unwrap().unwrap().content,
                recipes[0].content
            );
        }
        let packet = sync_store::export(&connection(&root)).unwrap();
        let mut peer = memory_db();
        sync_store::merge(&mut peer, packet, "sync").unwrap();
        assert_eq!(
            storage::load(&mut peer).unwrap().book.recipes.len(),
            if discard { 1 } else { 2 }
        );
    }
}

#[test]
fn invalid_conflict_alternative_is_set_aside_and_restore_resolves_all_heads() {
    let root = Root::new();
    let service = Service::open(&root).unwrap();
    let (recipes, bytes) = seed(&service);
    let conn = connection(&root);
    let packet = sync_store::export(&conn).unwrap();
    let current = packet
        .events
        .iter()
        .find(|e| e.recipe_id == recipes[0].id.0)
        .unwrap();
    let mut alternate = current.clone();
    alternate.id = "invalid-alternative".into();
    alternate.recipe.as_mut().unwrap()["createdAt"] = json!("invalid");
    conn.execute(
        "INSERT INTO history VALUES(?1,?2,?3)",
        params![
            alternate.id,
            alternate.recipe_id,
            serde_json::to_string(&alternate).unwrap()
        ],
    )
    .unwrap();
    conn.execute(
        "INSERT OR REPLACE INTO local VALUES('syncConflicts',?1)",
        [json!([{"recipeId":recipes[0].id.0,"versions":[current,alternate]}]).to_string()],
    )
    .unwrap();
    drop(conn);
    let snapshot = service.snapshot().unwrap();
    assert_eq!(snapshot.set_aside_count, 1);
    assert!(snapshot.conflicts.is_empty());
    assert_eq!(service.backup_report(&op()).unwrap().omitted, 1);
    let restored = service
        .restore(&service.preview_restore(&bytes, &op()).unwrap(), &op())
        .unwrap();
    assert_eq!(restored.set_aside_count, 0);
    assert!(restored.conflicts.is_empty());
    let mut destination = memory_db();
    sync_store::merge(
        &mut destination,
        sync_store::export(&connection(&root)).unwrap(),
        "sync",
    )
    .unwrap();
    assert!(
        sync_store::conflicts(&destination)
            .unwrap()
            .as_array()
            .unwrap()
            .is_empty()
    );
}

#[test]
fn corrupt_history_head_alone_cannot_break_library_and_can_be_repaired() {
    let root = Root::new();
    let service = Service::open(&root).unwrap();
    let (recipes, bytes) = seed(&service);
    let conn = connection(&root);
    let original: String = conn
        .query_row(
            "SELECT body FROM recipes WHERE id=?1",
            [&recipes[0].id.0],
            |r| r.get(0),
        )
        .unwrap();
    corrupt(&root, &recipes[0].id.0, false);
    conn.execute(
        "UPDATE recipes SET body=?2 WHERE id=?1",
        params![recipes[0].id.0, original],
    )
    .unwrap();
    let before = state(&conn);
    assert_eq!(service.snapshot().unwrap().set_aside_count, 1);
    assert_eq!(state(&conn), before);
    let restored = service
        .restore(&service.preview_restore(&bytes, &op()).unwrap(), &op())
        .unwrap();
    assert_eq!(restored.set_aside_count, 0);
    sync_store::export(&conn).unwrap();
}

#[test]
fn partial_restore_preserves_the_other_set_aside_recipe_and_recovery_snapshot() {
    let root = Root::new();
    let service = Service::open(&root).unwrap();
    let (recipes, _) = seed(&service);
    corrupt(&root, &recipes[0].id.0, false);
    let (unmatched, history) = corrupt(&root, &recipes[1].id.0, true);
    let conn = connection(&root);
    let previous = storage::previous(&conn).unwrap();
    assert_eq!(service.snapshot().unwrap().set_aside_count, 2);
    let bytes = backup::write(&recipes[..1]).unwrap();
    let after = service
        .restore(&service.preview_restore(&bytes, &op()).unwrap(), &op())
        .unwrap();
    assert_eq!(after.set_aside_count, 1);
    assert_eq!(after.summaries.len(), 1);
    assert_eq!(service.backup_report(&op()).unwrap().omitted, 1);
    assert_eq!(
        conn.query_row::<String, _, _>(
            "SELECT body FROM recipes WHERE id=?1",
            [&recipes[1].id.0],
            |r| r.get(0)
        )
        .unwrap(),
        unmatched
    );
    assert_eq!(
        conn.query_row::<i64, _, _>(
            "SELECT count(*) FROM history WHERE body=?1",
            [&history],
            |r| r.get(0)
        )
        .unwrap(),
        1
    );
    assert_eq!(storage::previous(&conn).unwrap(), previous);
    assert_eq!(
        sync_store::export(&conn).unwrap_err(),
        sync_store::SET_ASIDE_ERROR
    );
}
