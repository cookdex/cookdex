use cookdex_core::{
    adapters::AppPaths,
    backup, provider,
    recipe::{self, Recipe, RecipeContent, RecipeId},
    services::*,
    shopping,
};
use std::{path::PathBuf, sync::Arc};
struct Root(PathBuf);
impl Root {
    fn new() -> Self {
        Self(std::env::temp_dir().join(format!("cookdex-c3-{}", uuid::Uuid::new_v4())))
    }
}
impl AppPaths for Root {
    fn private_root(&self) -> std::result::Result<PathBuf, String> {
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
fn fixture() -> Vec<Recipe> {
    let v: serde_json::Value =
        serde_json::from_str(include_str!("../../../../tests/fixtures/corpus.json")).unwrap();
    v["recipes"]
        .as_array()
        .unwrap()
        .iter()
        .map(|r| Recipe::from_json(&serde_json::to_vec(r).unwrap()).unwrap())
        .collect()
}
fn op() -> Operation {
    Operation::default()
}
fn fields(title: &str) -> RecipeContent {
    RecipeContent {
        title: title.into(),
        description: String::new(),
        servings: String::new(),
        prep_time: String::new(),
        cook_time: String::new(),
        total_time: String::new(),
        source: String::new(),
        notes: String::new(),
        tags: vec![],
        ingredients: vec![],
        steps: vec![],
    }
}
fn seed(s: &Service) -> Snapshot {
    let bytes = backup::write(&fixture()).unwrap();
    s.restore(&s.preview_restore(&bytes, &op()).unwrap(), &op())
        .unwrap()
}

#[test]
fn library_checkpoint_exact_batch_snapshot_and_undo() {
    let root = Root::new();
    let service = Service::open(&root).unwrap();
    let mut recipes = Vec::new();
    for index in 0..12 {
        let mut r = fixture()[0].clone();
        r.id = RecipeId(uuid::Uuid::new_v4().to_string());
        r.content.title = format!("Library fixture {index}");
        r.content.ingredients[0].name = if index < 8 { "parm" } else { "parmesan" }.into();
        r.content.tags = vec!["Quick".into(), "quick".into(), "Dinner".into()];
        recipes.push(r);
    }
    let mut setup = cookdex_core::shopping_categories::Setup::default();
    setup.remember("parm", "spices").unwrap();
    let bytes = backup::write_with_setup(&recipes, Some(&setup)).unwrap();
    let initial = service
        .restore(&service.preview_restore(&bytes, &op()).unwrap(), &op())
        .unwrap();
    let (changed, undo) = service
        .change_library_names(
            initial.generation,
            false,
            &["parm".into()],
            Some("parmesan"),
            &op(),
        )
        .unwrap();
    assert_eq!(changed.generation, initial.generation + 1);
    assert_eq!(undo.count(), 8);
    let mut db = cookdex_core::storage::open(&root.0.join("flutter-v1/cookdex.sqlite3")).unwrap();
    let carried = cookdex_core::storage::load(&mut db)
        .unwrap()
        .book
        .shopping_setup;
    assert_eq!(
        carried.placements.get("parmesan").map(String::as_str),
        Some("spices")
    );
    assert_eq!(
        carried.placements.get("parm").map(String::as_str),
        Some("spices")
    );
    assert!(
        service
            .rolling_snapshots()
            .unwrap()
            .0
            .iter()
            .any(|e| e.reason == "before_library")
    );
    for (index, original) in recipes.iter().enumerate() {
        let actual = service.detail(&original.id).unwrap().unwrap();
        let mut expected = original.clone();
        if index < 8 {
            expected.content.ingredients[0].name = "parmesan".into();
            expected.revision += 1;
        }
        assert_eq!(actual, expected);
    }
    let restored = service
        .undo_library_names(changed.generation, &undo, &op())
        .unwrap();
    assert_eq!(
        cookdex_core::storage::load(&mut db)
            .unwrap()
            .book
            .shopping_setup,
        setup
    );
    for (index, original) in recipes.iter().enumerate() {
        let actual = service.detail(&original.id).unwrap().unwrap();
        let mut expected = original.clone();
        if index < 8 {
            expected.revision += 2;
        }
        assert_eq!(actual, expected);
    }
    let (merged, tag_undo) = service
        .change_library_names(
            restored.generation,
            true,
            &["Quick".into()],
            Some("quick"),
            &op(),
        )
        .unwrap();
    for original in &recipes {
        assert_eq!(
            service.detail(&original.id).unwrap().unwrap().content.tags,
            vec!["quick", "Dinner"]
        );
    }
    let tag_restored = service
        .undo_library_names(merged.generation, &tag_undo, &op())
        .unwrap();
    let (removed, remove_undo) = service
        .change_library_names(
            tag_restored.generation,
            true,
            &["Quick".into()],
            None,
            &op(),
        )
        .unwrap();
    assert_eq!(remove_undo.count(), 12);
    assert_eq!(
        service
            .detail(&recipes[0].id)
            .unwrap()
            .unwrap()
            .content
            .tags,
        vec!["quick", "Dinner"]
    );
    service
        .undo_library_names(removed.generation, &remove_undo, &op())
        .unwrap();
    assert_eq!(
        service
            .detail(&recipes[0].id)
            .unwrap()
            .unwrap()
            .content
            .tags,
        recipes[0].content.tags
    );
    assert!(matches!(
        service.change_library_names(
            initial.generation,
            false,
            &["parm".into()],
            Some("new"),
            &op()
        ),
        Err(Error::StaleWrite)
    ));
}

#[test]
fn library_checkpoint_overlapping_rows_sections_tags_and_undo() {
    let root = Root::new();
    let service = Service::open(&root).unwrap();
    let mut recipes = Vec::new();
    for index in 0..12 {
        let mut r = fixture()[0].clone();
        r.id = RecipeId(uuid::Uuid::new_v4().to_string());
        r.content.title = format!("Sectioned egg bake {index}");
        r.content.tags = vec!["Weeknight".into(), "vegetarian".into(), "weeknight".into()];
        let template = r.content.ingredients[0].clone();
        r.content.ingredients = [
            ("Eggs", "2", "Filling"),
            ("Egg", "1", "Filling"),
            ("Eggs", "3", "Topping"),
        ]
        .into_iter()
        .map(|(name, amount, section)| {
            let mut row = template.clone();
            row.name = name.into();
            row.amount = recipe::Amount::parse_exact(amount).unwrap();
            row.unit.clear();
            row.prep_note = "beaten".into();
            row.optional = section == "Topping";
            row.section = section.into();
            row
        })
        .collect();
        r.validate().unwrap();
        recipes.push(r);
    }
    let bytes = backup::write(&recipes).unwrap();
    let mut state = service
        .restore(&service.preview_restore(&bytes, &op()).unwrap(), &op())
        .unwrap();
    for target in ["Egg", "large eggs"] {
        let before: Vec<_> = recipes
            .iter()
            .map(|r| service.detail(&r.id).unwrap().unwrap())
            .collect();
        let (changed, undo) = service
            .change_library_names(
                state.generation,
                false,
                &["Eggs".into()],
                Some(target),
                &op(),
            )
            .unwrap();
        assert_eq!(undo.count(), 12); // Each recipe contains two source rows and one destination row.
        assert_eq!(changed.generation, state.generation + 1);
        for original in &before {
            let mut expected = original.clone();
            expected.revision += 1;
            for row in &mut expected.content.ingredients {
                if row.name == "Eggs" {
                    row.name = target.into();
                }
            }
            // Complete equality protects every row, amount, note, section, position and timestamp.
            assert_eq!(service.detail(&original.id).unwrap().unwrap(), expected);
        }
        state = service
            .undo_library_names(changed.generation, &undo, &op())
            .unwrap();
        for original in &before {
            let mut expected = original.clone();
            expected.revision += 2;
            assert_eq!(service.detail(&original.id).unwrap().unwrap(), expected);
        }
    }
    let before: Vec<_> = recipes
        .iter()
        .map(|r| service.detail(&r.id).unwrap().unwrap())
        .collect();
    let (changed, undo) = service
        .change_library_names(
            state.generation,
            true,
            &["Weeknight".into()],
            Some("weeknight"),
            &op(),
        )
        .unwrap();
    assert_eq!(undo.count(), 12);
    for original in &before {
        let mut expected = original.clone();
        expected.revision += 1;
        expected.content.tags = vec!["weeknight".into(), "vegetarian".into()];
        assert_eq!(service.detail(&original.id).unwrap().unwrap(), expected);
    }
    service
        .undo_library_names(changed.generation, &undo, &op())
        .unwrap();
    for original in &before {
        let mut expected = original.clone();
        expected.revision += 2;
        assert_eq!(service.detail(&original.id).unwrap().unwrap(), expected);
    }
}

#[test]
fn library_checkpoint_add_tag_batch_snapshot_sync_and_undo() {
    use cookdex_core::{storage, sync_store};
    let root = Root::new();
    let service = Service::open(&root).unwrap();
    let recipes: Vec<_> = (0..24)
        .map(|i| {
            let mut r = fixture()[0].clone();
            r.id = RecipeId(uuid::Uuid::new_v4().to_string());
            r.content.tags = if i < 8 {
                vec!["weeknight".into(), "quick".into()]
            } else {
                vec!["quick".into()]
            };
            r
        })
        .collect();
    let bytes = backup::write(&recipes).unwrap();
    let initial = service
        .restore(&service.preview_restore(&bytes, &op()).unwrap(), &op())
        .unwrap();
    let ids: Vec<_> = recipes.iter().map(|r| r.id.clone()).collect();
    let db = storage::open(&root.0.join("flutter-v1/cookdex.sqlite3")).unwrap();
    let events_before = sync_store::export(&db).unwrap().events;
    let (changed, undo) = service
        .add_library_tag(initial.generation, &ids, "weeknight", &op())
        .unwrap();
    assert_eq!(changed.generation, initial.generation + 1);
    assert_eq!(undo.count(), 16);
    assert!(
        service
            .rolling_snapshots()
            .unwrap()
            .0
            .iter()
            .any(|s| s.reason == "before_library")
    );
    let events_after = sync_store::export(&db).unwrap().events;
    assert_eq!(events_after.len(), events_before.len() + 16);
    assert!(events_before.iter().all(|e| events_after.contains(e)));
    for (i, r) in recipes.iter().enumerate() {
        let mut expected = r.clone();
        if i >= 8 {
            expected.content.tags.push("weeknight".into());
            expected.revision += 1;
        }
        assert_eq!(service.detail(&r.id).unwrap().unwrap(), expected);
    }
    let restored = service
        .undo_library_names(changed.generation, &undo, &op())
        .unwrap();
    assert_eq!(
        sync_store::export(&db).unwrap().events.len(),
        events_after.len() + 16
    );
    for (i, r) in recipes.iter().enumerate() {
        let mut expected = r.clone();
        if i >= 8 {
            expected.revision += 2;
        }
        assert_eq!(service.detail(&r.id).unwrap().unwrap(), expected);
    }
    let cancelled = op();
    cancelled.cancel();
    assert!(matches!(
        service.add_library_tag(restored.generation, &ids, "new tag", &cancelled),
        Err(Error::Cancelled)
    ));
    assert_eq!(service.snapshot().unwrap(), restored);
    let (created, undo) = service
        .add_library_tag(restored.generation, &ids, "new tag", &op())
        .unwrap();
    assert_eq!(undo.count(), 24);
    assert!(
        created
            .summaries
            .iter()
            .all(|r| r.tags.contains(&"new tag".to_owned()))
    );
    let restored = service
        .undo_library_names(created.generation, &undo, &op())
        .unwrap();
    assert!(
        restored
            .summaries
            .iter()
            .all(|r| !r.tags.contains(&"new tag".to_owned()))
    );
}

#[test]
fn library_checkpoint_snapshot_failure_and_cancellation_leave_names_intact() {
    let root = Root::new();
    let s = Service::open(&root).unwrap();
    let initial = seed(&s);
    let name = initial.summaries[0].ingredients[0].clone();
    let cancelled = op();
    cancelled.cancel();
    assert!(matches!(
        s.change_library_names(
            initial.generation,
            false,
            &[name.clone()],
            Some("new name"),
            &cancelled
        ),
        Err(Error::Cancelled)
    ));
    let snapshot_path = root.0.join("flutter-v1/snapshots");
    std::fs::remove_dir_all(&snapshot_path).unwrap();
    std::fs::write(&snapshot_path, b"synthetic unavailable directory").unwrap();
    assert!(
        s.change_library_names(initial.generation, false, &[name], Some("new name"), &op())
            .is_err()
    );
    assert!(
        s.add_library_tag(
            initial.generation,
            &[initial.summaries[0].id.clone()],
            "new tag",
            &op()
        )
        .is_err()
    );
    assert_eq!(s.snapshot().unwrap(), initial);
}

#[test]
fn editor_save_reopen_exact_amounts_and_stale_original_can_only_save_as_copy() {
    let root = Root::new();
    let service = Service::open(&root).unwrap();
    let mut content = fixture()[0].content.clone();
    content.tags = content
        .tags
        .iter()
        .map(|tag| {
            tag.split_whitespace()
                .collect::<Vec<_>>()
                .join(" ")
                .to_lowercase()
        })
        .collect();
    let first = service.save(0, None, content.clone(), &op()).unwrap();
    let id = first.summaries[0].id.clone();
    let base = service.detail(&id).unwrap().unwrap();
    assert_eq!(base.content, content);
    drop(service);
    let service = Service::open(&root).unwrap();
    assert_eq!(service.detail(&id).unwrap().unwrap().content, content);
    let mut inputs = vec![None; content.ingredients.len()];
    inputs[0] = Some("0.33".into());
    let changed = content.parse_editor(&inputs).unwrap();
    assert_eq!(changed.ingredients[0].amount.text(), "1/3");
    assert_eq!(changed.ingredients[1].amount.text(), "33/100");
    let saved = service
        .save(first.generation, Some(base.clone()), changed.clone(), &op())
        .unwrap();
    assert_eq!(service.detail(&id).unwrap().unwrap().content, changed);
    assert_eq!(
        service.save(saved.generation, Some(base.clone()), content.clone(), &op()),
        Err(Error::StaleWrite)
    );
    let current = service.detail(&id).unwrap().unwrap();
    let deleted = service.delete(saved.generation, &id, &op()).unwrap();
    assert_eq!(
        service.save(deleted.generation, Some(current), content.clone(), &op()),
        Err(Error::StaleWrite)
    );
    let copied = service
        .save(deleted.generation, None, content.clone(), &op())
        .unwrap();
    assert_ne!(copied.summaries[0].id, id);
    assert_eq!(
        service
            .detail(&copied.summaries[0].id)
            .unwrap()
            .unwrap()
            .content,
        content
    );
}

#[test]
fn zip_corpus_round_trip_and_hostile_headers_fail_closed() {
    let recipes = fixture();
    let bytes = backup::write(&recipes).unwrap();
    assert_eq!(backup::read(&bytes).unwrap(), recipes);
    assert_eq!(backup::read(&backup::write(&[]).unwrap()).unwrap(), vec![]);
    for cut in [0, 1, 21, bytes.len() - 1] {
        assert!(backup::read(&bytes[..cut]).is_err());
    }
    let directory =
        u32::from_le_bytes(bytes[bytes.len() - 6..bytes.len() - 2].try_into().unwrap()) as usize;
    for (offset, value) in [
        (0, 0u8),
        (6, 1),
        (8, 99),
        (14, 0),
        (26, 0),
        (directory, 0),
        (directory + 8, 1),
        (directory + 10, 99),
        (directory + 16, 0),
        (directory + 34, 1),
        (directory + 42, 255),
        (bytes.len() - 18, 1),
    ] {
        let mut bad = bytes.clone();
        bad[offset] = value;
        if bad != bytes {
            assert!(backup::read(&bad).is_err(), "offset {offset}");
        }
    }
    let mut bad = bytes.clone();
    bad[30] = b'.';
    bad[directory + 46] = b'.';
    assert!(backup::read(&bad).is_err());
    let mut bad = bytes.clone();
    bad[30] = b'/';
    bad[directory + 46] = b'/';
    assert!(backup::read(&bad).is_err());
    let mut bad = bytes.clone();
    bad[directory + 24..directory + 28].copy_from_slice(&u32::MAX.to_le_bytes());
    assert!(backup::read(&bad).is_err());
    let mut duplicate = recipes.clone();
    duplicate.push(recipes[0].clone());
    assert!(backup::write(&duplicate).is_err());
}
#[test]
fn zip_count_and_byte_limits_are_enforced() {
    let mut recipes = Vec::new();
    for i in 0..10000 {
        let mut r = Recipe::new(fields("tiny"), "2026-10-08T00:00:00Z").unwrap();
        r.id = RecipeId(format!("r{i}"));
        recipes.push(r);
    }
    assert_eq!(
        backup::read(&backup::write(&recipes).unwrap())
            .unwrap()
            .len(),
        10000
    );
    recipes.push(Recipe::new(fields("extra"), "2026-10-08T00:00:00Z").unwrap());
    assert!(backup::write(&recipes).is_err());
    assert_eq!(
        backup::read(&vec![0; backup::MAX_ZIP_BYTES + 1]),
        Err(Error::Limit)
    );
}
#[test]
fn merge_reports_preserve_fields_and_use_instant_comparison() {
    let root = Root::new();
    let s = Service::open(&root).unwrap();
    let snapshot = seed(&s);
    let recipes = fixture();
    let p = s
        .preview_restore(&backup::write(&recipes).unwrap(), &op())
        .unwrap();
    assert_eq!(p.report.skipped, 2);
    let mut incoming = recipes.clone();
    incoming[0].content.notes = "changed same date".into();
    incoming[1].updated_at = "2030-01-01T00:00:00Z".into();
    incoming[1].revision += 1;
    let p = s
        .preview_restore(&backup::write(&incoming).unwrap(), &op())
        .unwrap();
    assert_eq!(p.report.updated, 1);
    assert_eq!(p.report.conflicts, vec![recipes[0].id.clone()]);
    let current = s.restore(&p, &op()).unwrap();
    assert_eq!(current.generation, snapshot.generation + 1);
    assert_eq!(s.detail(&recipes[0].id).unwrap(), Some(recipes[0].clone()));
    assert_eq!(s.detail(&recipes[1].id).unwrap(), Some(incoming[1].clone()));
    assert_eq!(s.restore(&p, &op()), Err(Error::StaleWrite));
}
#[test]
fn single_import_requires_review_and_replacement_keeps_identity() {
    let root = Root::new();
    let s = Service::open(&root).unwrap();
    let a = s.import_one(0, fields("Stew"), None, &op()).unwrap();
    let id = &a.summaries[0].id;
    let original = s.detail(id).unwrap().unwrap();
    assert_eq!(
        s.import_one(a.generation, fields(" stew "), None, &op()),
        Err(Error::Conflict)
    );
    let b = s
        .import_one(
            a.generation,
            fields(" stew "),
            Some(DuplicateChoice::Replace { id: id.clone() }),
            &op(),
        )
        .unwrap();
    let replaced = s.detail(id).unwrap().unwrap();
    assert_eq!(original.created_at, replaced.created_at);
    assert_eq!(replaced.revision, original.revision + 1);
    let c = s
        .import_one(
            b.generation,
            fields("stew"),
            Some(DuplicateChoice::KeepBoth),
            &op(),
        )
        .unwrap();
    assert_eq!(c.summaries.len(), 2);
    assert_ne!(c.summaries[0].id, c.summaries[1].id);
    assert_eq!(
        s.import_one(
            c.generation,
            fields("new name"),
            Some(DuplicateChoice::Replace { id: id.clone() }),
            &op()
        ),
        Err(Error::StaleWrite)
    );
}
#[test]
fn batch_delete_500_is_one_commit_with_a_complete_recoverable_snapshot() {
    let root = Root::new();
    let s = Service::open(&root).unwrap();
    let mut recipes = vec![];
    for i in 0..500 {
        let mut r = fixture()[i % 2].clone();
        r.id = RecipeId(format!("batch-{i:03}"));
        recipes.push(r);
    }
    let before = s
        .restore(
            &s.preview_restore(&backup::write(&recipes).unwrap(), &op())
                .unwrap(),
            &op(),
        )
        .unwrap();
    let subscription = s.subscribe().unwrap();
    let ids: Vec<_> = recipes.iter().map(|r| r.id.clone()).collect();
    let after = s.delete_many(before.generation, &ids, &op()).unwrap();
    assert_eq!(after.generation, before.generation + 1);
    assert!(after.summaries.is_empty());
    let event = subscription.receiver.recv().unwrap();
    assert_eq!(event.deleted, ids);
    assert!(subscription.receiver.try_recv().is_err());
    let entry = s.rolling_snapshots().unwrap().0.pop().unwrap();
    assert_eq!(entry.reason, "before_delete");
    assert_eq!(entry.recipe_count, 500);
    let bytes = s.rolling_snapshot_bytes(&entry.id).unwrap();
    assert_eq!(backup::read(&bytes).unwrap(), recipes);
    let restored = s
        .restore(&s.preview_restore(&bytes, &op()).unwrap(), &op())
        .unwrap();
    assert_eq!(restored.summaries.len(), 500);
    for r in recipes {
        assert_eq!(s.detail(&r.id).unwrap(), Some(r));
    }
}

#[test]
fn batch_delete_rejects_stale_missing_duplicate_cancelled_and_failed_snapshot() {
    let root = Root::new();
    let s = Service::open(&root).unwrap();
    let before = seed(&s);
    let ids: Vec<_> = before.summaries.iter().map(|r| r.id.clone()).collect();
    let snapshots = s.rolling_snapshots().unwrap().0.len();
    assert_eq!(s.delete_many(0, &ids, &op()), Err(Error::StaleWrite));
    assert_eq!(
        s.delete_many(
            before.generation,
            &[ids[0].clone(), RecipeId("missing".into())],
            &op()
        ),
        Err(Error::StaleWrite)
    );
    assert_eq!(
        s.delete_many(before.generation, &[ids[0].clone(), ids[0].clone()], &op()),
        Err(Error::Validation)
    );
    let cancelled = op();
    cancelled.cancel();
    assert_eq!(
        s.delete_many(before.generation, &ids, &cancelled),
        Err(Error::Cancelled)
    );
    assert_eq!(s.rolling_snapshots().unwrap().0.len(), snapshots);
    let snapshot_path = root.0.join("flutter-v1/snapshots");
    std::fs::remove_dir_all(&snapshot_path).unwrap();
    std::fs::write(&snapshot_path, b"synthetic unavailable directory").unwrap();
    assert!(s.delete_many(before.generation, &ids, &op()).is_err());
    assert_eq!(s.snapshot().unwrap(), before);
}

#[test]
fn targeted_writes_preserve_unrelated_rows_and_previous_save() {
    let root = Root::new();
    let s = Service::open(&root).unwrap();
    let initial = seed(&s);
    let original = s.snapshot().unwrap();
    let id = original.summaries[0].id.clone();
    let other = s.detail(&original.summaries[1].id).unwrap().unwrap();
    let db = rusqlite::Connection::open(root.0.join("flutter-v1/cookdex.sqlite3")).unwrap();
    // Prime again after installing a trigger, so the external-version change
    // cannot accidentally make the test exercise only the uncached path.
    db.execute_batch("CREATE TRIGGER guard_other BEFORE UPDATE ON recipes WHEN OLD.id != (SELECT id FROM recipes ORDER BY id LIMIT 1) BEGIN SELECT RAISE(ABORT,'unrelated row rewritten'); END;").unwrap();
    s.snapshot().unwrap();
    let saved = s.favorite(initial.generation, &id, true, &op()).unwrap();
    assert_eq!(s.detail(&other.id).unwrap(), Some(other));
    let previous: serde_json::Value = serde_json::from_str(
        &db.query_row("SELECT body FROM local WHERE key='previous'", [], |r| {
            r.get::<_, String>(0)
        })
        .unwrap(),
    )
    .unwrap();
    assert_eq!(
        previous["book"]["recipes"].as_array().unwrap().len(),
        original.summaries.len()
    );
    let before =
        Recipe::from_json(&serde_json::to_vec(&previous["book"]["recipes"][0]).unwrap()).unwrap();
    assert_eq!(before.updated_at, original.summaries[0].updated_at);
    assert_eq!(s.snapshot().unwrap(), saved);
    // An external change without a generation increment must invalidate the
    // validation cache and prevent writing a now unreadable target.
    db.execute("UPDATE recipes SET body='{}' WHERE id=?1", [&id.0])
        .unwrap();
    assert_eq!(
        s.favorite(saved.generation, &id, false, &op()),
        Err(Error::StaleWrite)
    );
    assert_eq!(s.snapshot().unwrap().set_aside_count, 1);
}

#[test]
fn cancellation_staleness_validation_and_database_failure_are_atomic() {
    let root = Root::new();
    let s = Service::open(&root).unwrap();
    let before = seed(&s);
    let cancelled = op();
    assert!(cancelled.cancel());
    assert_eq!(
        s.delete(before.generation, &before.summaries[0].id, &cancelled),
        Err(Error::Cancelled)
    );
    assert_eq!(
        s.save(before.generation, None, fields(""), &op()),
        Err(Error::Validation)
    );
    assert_eq!(
        s.favorite(0, &before.summaries[0].id, true, &op()),
        Err(Error::StaleWrite)
    );
    assert_eq!(s.snapshot().unwrap(), before);
    let db = rusqlite::Connection::open(root.0.join("flutter-v1/cookdex.sqlite3")).unwrap();
    db.execute_batch("CREATE TRIGGER abort_write BEFORE UPDATE ON state BEGIN SELECT RAISE(ABORT,'synthetic failure'); END;").unwrap();
    assert!(
        s.delete(before.generation, &before.summaries[0].id, &op())
            .is_err()
    );
    assert_eq!(s.snapshot().unwrap(), before);
    db.execute_batch("DROP TRIGGER abort_write").unwrap();
    drop(db);
    let token = op();
    let after = s
        .favorite(before.generation, &before.summaries[0].id, true, &token)
        .unwrap();
    assert!(!token.cancel());
    assert_eq!(s.snapshot().unwrap(), after);
}
#[test]
fn concurrent_mutations_commit_once_and_subscription_has_no_handshake_gap() {
    let root = Root::new();
    let s = Arc::new(Service::open(&root).unwrap());
    let sub = s.subscribe().unwrap();
    assert_eq!(sub.snapshot.generation, 0);
    let a = s.clone();
    let b = s.clone();
    let x = std::thread::spawn(move || a.save(0, None, fields("A"), &op()));
    let y = std::thread::spawn(move || b.save(0, None, fields("B"), &op()));
    let (x, y) = (x.join().unwrap(), y.join().unwrap());
    assert_ne!(x.is_ok(), y.is_ok());
    assert_eq!(sub.receiver.recv().unwrap().generation, 1);
    assert!(sub.receiver.try_recv().is_err());
    let snap = s.snapshot().unwrap();
    let sub = s.subscribe().unwrap();
    assert_eq!(sub.snapshot, snap);
    let id = &snap.summaries[0].id;
    s.delete(snap.generation, id, &op()).unwrap();
    let change = sub.receiver.recv().unwrap();
    assert_eq!(change.deleted, vec![id.clone()]);
    assert_eq!(change.generation, 2);
}
fn ingredient(name: &str, amount: &str, unit: &str) -> recipe::Ingredient {
    recipe::Ingredient {
        amount: recipe::Amount::parse_exact(amount).unwrap(),
        unit: unit.into(),
        name: name.into(),
        prep_note: "remove for shopping".into(),
        optional: true,
        section: "any".into(),
    }
}
#[test]
fn exact_shopping_families_mixed_measures_and_unique_sources() {
    let mut r = Recipe::new(fields("first"), "2026-10-08T00:00:00Z").unwrap();
    r.content.ingredients = vec![
        ingredient(" Sugar ", "1", "cup"),
        ingredient("sugar", "8", "tbsp"),
        ingredient("sugar", "1", "g"),
        ingredient("sugar", "0.5", "kg"),
        ingredient("salt", "", ""),
        ingredient("salt", "to taste", ""),
        ingredient("cream", "33/100", "cup"),
    ];
    let items = shopping::add(&[], &r, &[0, 1, 2, 3, 4, 5, 6]).unwrap();
    assert_eq!(items.len(), 4);
    assert_eq!(items[0].quantity_text(), "1 1/2 cups + 501/1000 kg");
    assert_eq!(items[0].contributors.len(), 1);
    assert_eq!(items[3].quantity_text(), "33/100 cup");
    let mut r2 = r.clone();
    r2.id = RecipeId("second".into());
    let items = shopping::add(&items, &r2, &[0]).unwrap();
    assert_eq!(items[0].contributors.len(), 2);
    assert_eq!(items[0].quantity_text(), "2 1/2 cups + 501/1000 kg");
    let mut r = Recipe::new(fields("units"), "2026-10-08T00:00:00Z").unwrap();
    r.content.ingredients = vec![
        ingredient("a", "1", "l"),
        ingredient("a", "500", "ml"),
        ingredient("b", "1", "lb"),
        ingredient("b", "16", "oz"),
        ingredient("c", "1", "cup"),
        ingredient("c", "1", "tsp"),
    ];
    let items = shopping::add(&[], &r, &[0, 1, 2, 3, 4, 5]).unwrap();
    assert_eq!(items[0].quantity_text(), "1 1/2 l");
    assert_eq!(items[1].quantity_text(), "2 lb");
    assert_eq!(items[2].quantity_text(), "1 cup + 1 tsp");
}
#[test]
fn shopping_detachment_targeted_undo_recovery_and_restart_preserve_sources() {
    let root = Root::new();
    let s = Service::open(&root).unwrap();
    let mut f = fields("Soup");
    f.ingredients = vec![ingredient("cream", "33/100", "cup")];
    let snap = s.save(0, None, f, &op()).unwrap();
    let recipe_id = snap.summaries[0].id.clone();
    let added = s
        .add_shopping(snap.generation, &recipe_id, &[0], &op())
        .unwrap();
    let id = added.snapshot.shopping[0].id.clone();
    let checked = s
        .edit_shopping(
            added.snapshot.generation,
            ShoppingEdit::Check {
                ids: vec![id.clone()],
                checked: true,
            },
            &op(),
        )
        .unwrap();
    let summed = s
        .add_shopping(checked.snapshot.generation, &recipe_id, &[0], &op())
        .unwrap();
    assert!(!summed.snapshot.shopping[0].checked);
    assert_eq!(summed.snapshot.shopping[0].quantity_text(), "33/50 cup");
    let detached = s
        .edit_shopping(
            summed.snapshot.generation,
            ShoppingEdit::Edit {
                id: id.clone(),
                text: "edited cream".into(),
            },
            &op(),
        )
        .unwrap();
    assert!(detached.snapshot.shopping[0].contributors.is_empty());
    assert_eq!(
        s.undo_shopping(detached.snapshot.generation, &summed.undo, &op()),
        Err(Error::StaleWrite)
    );
    let other = s
        .edit_shopping(
            detached.snapshot.generation,
            ShoppingEdit::AddManual {
                text: "unrelated".into(),
            },
            &op(),
        )
        .unwrap();
    let undone = s
        .undo_shopping(other.snapshot.generation, &detached.undo, &op())
        .unwrap();
    assert_eq!(undone.shopping.len(), 2);
    assert_eq!(undone.shopping[0].contributors, vec![recipe_id.clone()]);
    let removed = s
        .edit_shopping(
            undone.generation,
            ShoppingEdit::Remove { ids: vec![id] },
            &op(),
        )
        .unwrap();
    let recovered = s.recover(removed.snapshot.generation, &op()).unwrap();
    assert_eq!(recovered.shopping, undone.shopping);
    drop(s);
    let s = Service::open(&root).unwrap();
    assert_eq!(s.snapshot().unwrap(), recovered);
    let deleted = s.delete(recovered.generation, &recipe_id, &op()).unwrap();
    s.recover(deleted.generation, &op()).unwrap();
    let r = s.detail(&recipe_id).unwrap().unwrap();
    assert_eq!(r.content.ingredients[0].amount.text(), "33/100");
    assert!(r.revision > 1);
}
fn written() -> serde_json::Value {
    serde_json::json!({"title":"Soup","description":"","servings":"","prepTime":"","cookTime":"","totalTime":"","source":"","tags":[],"notes":"","steps":[],"ingredients":[{"amount":"0.33","unit":"cup","name":"cream","prepNote":"","optional":false,"section":""}]})
}
fn envelope(v: serde_json::Value) -> Vec<u8> {
    serde_json::to_vec(&serde_json::json!({"status":"completed","steps":[{"type":"model_output","content":[{"type":"text","text":v.to_string()}]}]})).unwrap()
}
fn input() -> provider::Input {
    provider::Input {
        text: "selected only".into(),
        source: String::new(),
        target_title: String::new(),
        photos: vec![],
        mode: provider::Mode::Recipe,
        existing_tags: vec![],
    }
}
#[test]
fn provider_shape_written_amounts_retry_and_secret_free_errors() {
    use std::cell::RefCell;
    struct Mock {
        calls: RefCell<Vec<Vec<u8>>>,
        replies: RefCell<Vec<(u16, Vec<u8>)>>,
    }
    impl provider::Transport for Mock {
        fn send(&self, b: &[u8]) -> Result<(u16, Vec<u8>)> {
            self.calls.borrow_mut().push(b.to_vec());
            Ok(self.replies.borrow_mut().remove(0))
        }
    }
    let mock = Mock {
        calls: RefCell::new(vec![]),
        replies: RefCell::new(vec![
            (200, envelope(serde_json::json!({}))),
            (200, envelope(written())),
        ]),
    };
    let provider::Output::Recipe(r) =
        provider::extract(&input(), "test-model", &mock, &op()).unwrap();
    assert_eq!(r.content.ingredients[0].amount.text(), "1/3");
    assert_eq!(mock.calls.borrow().len(), 2);
    let body: serde_json::Value = serde_json::from_slice(&mock.calls.borrow()[0]).unwrap();
    assert_eq!(body["store"], false);
    assert_eq!(
        body["response_format"]["schema"]["properties"]["ingredients"]["items"]["properties"]["amount"]
            ["type"],
        "string"
    );
    assert!(body.to_string().contains("selected only"));
    for status in [400, 401, 403, 404, 429, 500] {
        let mock = Mock {
            calls: RefCell::new(vec![]),
            replies: RefCell::new(vec![(status, b"SECRET provider response".to_vec())]),
        };
        let e = provider::extract(&input(), "test-model", &mock, &op()).unwrap_err();
        assert!(!e.to_string().contains("SECRET"));
        assert_eq!(mock.calls.borrow().len(), 1);
    }
    let cancelled = op();
    cancelled.cancel();
    assert_eq!(
        provider::extract(&input(), "test-model", &mock, &cancelled),
        Err(Error::Cancelled)
    );
    let mut input = input();
    input.photos = vec![provider::Photo {
        mime_type: "image/png".into(),
        bytes: vec![1, 2, 3],
    }];
    assert!(provider::request(&input, "test-model", false).is_err());
}
#[test]
fn provider_cancelled_during_transport_ignores_late_success() {
    struct Late<'a>(&'a Operation);
    impl provider::Transport for Late<'_> {
        fn send(&self, _: &[u8]) -> Result<(u16, Vec<u8>)> {
            self.0.cancel();
            Ok((200, envelope(written())))
        }
    }
    let token = op();
    assert_eq!(
        provider::extract(&input(), "test-model", &Late(&token), &token),
        Err(Error::Cancelled)
    );
}

#[test]
fn prepared_photos_enforce_exact_base64_aggregate_and_count_boundaries() {
    let photo = |len: usize| {
        let mut bytes = vec![0; len];
        bytes[..3].copy_from_slice(&[255, 216, 255]);
        bytes[len - 2..].copy_from_slice(&[255, 217]);
        provider::Photo {
            mime_type: "image/jpeg".into(),
            bytes,
        }
    };
    let mut input = input();
    input.photos = vec![photo(9 * 1024 * 1024)];
    assert!(provider::request(&input, "test-model", false).is_ok());
    input.photos = vec![photo(9 * 1024 * 1024 + 1)];
    assert_eq!(
        provider::request(&input, "test-model", false),
        Err(Error::Limit)
    );
    input.photos = vec![photo(9 * 1024 * 1024 / 8); 8];
    assert!(provider::request(&input, "test-model", false).is_ok());
    input.photos.push(photo(6));
    assert_eq!(
        provider::request(&input, "test-model", false),
        Err(Error::Limit)
    );
}

#[test]
fn canonical_collection_exact_32_mib_and_one_byte_over() {
    let mut r = Recipe::new(fields("bounded"), "2026-10-08T00:00:00Z").unwrap();
    r.content.steps = vec!["x".repeat(30_000); 1118];
    let envelope = br#"{"schemaVersion":1,"recipes":[],"shopping":[],"deletedRecipes":[]}"#.len();
    let padding = recipe::MAX_COLLECTION_BYTES - envelope - r.to_json().unwrap().len();
    assert!(padding <= 20_000);
    r.content.notes = "n".repeat(padding);
    let bytes = backup::write(std::slice::from_ref(&r)).unwrap();
    assert_eq!(backup::read(&bytes).unwrap(), vec![r.clone()]);
    r.content.notes.push('n');
    assert_eq!(backup::write(&[r]), Err(Error::Limit));
}

#[test]
fn reviewed_tags_keep_spelling_without_rewriting_restored_recipes() {
    let root = Root::new();
    let service = Service::open(&root).unwrap();
    let mut recipes = fixture();
    for r in &mut recipes {
        r.content.tags = vec!["Dinner".into(), "DINNER".into(), "Quick".into()];
    }
    let bytes = backup::write(&recipes).unwrap();
    let restored = service
        .restore(&service.preview_restore(&bytes, &op()).unwrap(), &op())
        .unwrap();
    let original = service.detail(&recipes[0].id).unwrap().unwrap();
    assert_eq!(original.content.tags, vec!["Dinner", "DINNER", "Quick"]);
    let saved = service
        .save(
            restored.generation,
            Some(original.clone()),
            original.content.clone(),
            &op(),
        )
        .unwrap();
    assert_eq!(
        service.detail(&original.id).unwrap().unwrap().content.tags,
        vec!["Dinner", "DINNER", "Quick"]
    );
    assert_eq!(
        service
            .detail(&recipes[1].id)
            .unwrap()
            .unwrap()
            .content
            .tags,
        recipes[1].content.tags
    );
    let mut imported = fields("New import");
    imported.tags = vec![" VEGAN ".into(), "Vegan".into()];
    let result = service
        .import_one(saved.generation, imported, None, &op())
        .unwrap();
    assert_eq!(
        result
            .summaries
            .iter()
            .find(|r| r.title == "New import")
            .unwrap()
            .tags,
        vec![" VEGAN ", "Vegan"]
    );
}

#[test]
fn remote_url_tool_is_rejected_and_downloaded_text_uses_no_tools() {
    let mut request = input();
    request.mode = provider::Mode::UrlRecipe;
    for url in ["http://example.com/recipe", "https://example.com/recipe"] {
        request.source = url.into();
        assert_eq!(
            provider::request(&request, "test-model", false),
            Err(Error::Validation)
        );
    }
    request.mode = provider::Mode::Recipe;
    request.text = "Securely downloaded recipe text".into();
    let body: serde_json::Value =
        serde_json::from_slice(&provider::request(&request, "test-model", false).unwrap()).unwrap();
    assert!(body.get("tools").is_none());
    assert!(
        !body["system_instruction"]
            .as_str()
            .unwrap()
            .contains("using URL context")
    );
}

#[test]
fn ai_review_policy_filters_tags_and_keeps_guess_markers_outside_recipe() {
    let mut input = input();
    input.existing_tags = vec!["Family Favorite".into()];
    let body: serde_json::Value =
        serde_json::from_slice(&provider::request(&input, "test-model", false).unwrap()).unwrap();
    let context: serde_json::Value =
        serde_json::from_str(body["input"][0]["text"].as_str().unwrap()).unwrap();
    assert!(
        context["allowedTags"]
            .as_array()
            .unwrap()
            .contains(&serde_json::json!("family favorite"))
    );
    assert!(
        body["system_instruction"]
            .as_str()
            .unwrap()
            .contains("short, simple steps")
    );
    assert!(
        body["system_instruction"]
            .as_str()
            .unwrap()
            .contains("reasonably confident")
    );
    let mut source = written();
    source["servings"] = serde_json::json!("4");
    source["totalTime"] = serde_json::json!("20 minutes");
    source["tags"] = serde_json::json!([
        "NEW INVENTED TAG",
        "FAMILY FAVORITE",
        "Soup",
        "quick",
        "dinner"
    ]);
    source["steps"] = serde_json::json!(["Combine ingredients.", "Cook until ready."]);
    source["aiGuessedFields"] = serde_json::json!(["servings", "totalTime", "tags", "title"]);
    source["aiGuessedSteps"] = serde_json::json!([0, 1, 99]);
    let bytes = envelope(source);
    let provider::Output::Recipe(mut recipe) =
        provider::response(&bytes, &provider::Mode::Recipe).unwrap();
    let review = provider::review_response(&bytes, &input, &mut recipe).unwrap();
    assert_eq!(recipe.content.tags, ["family favorite", "soup", "quick"]);
    assert_eq!(review.ai_guessed_fields, ["servings", "tags", "totalTime"]);
    assert_eq!(review.ai_guessed_steps, [0, 1]);
    let mut source = written();
    source["steps"] = serde_json::json!(["", "Mix.", "Bake."]);
    source["aiGuessedSteps"] = serde_json::json!([1, 2]);
    let bytes = envelope(source);
    let provider::Output::Recipe(mut parsed) =
        provider::response(&bytes, &provider::Mode::Recipe).unwrap();
    assert_eq!(
        provider::review_response(&bytes, &input, &mut parsed)
            .unwrap()
            .ai_guessed_steps,
        [0, 1]
    );
    assert!(
        !String::from_utf8(recipe.to_json().unwrap())
            .unwrap()
            .contains("Guessed")
    );
}

#[test]
fn ai_context_preserves_unparseable_embedded_data_and_reports_actual_failures() {
    let context = cookdex_core::recipe::web::ai_context(
        r#"<script type="application/ld+json">{broken recipe data}</script><p>1 medium onion</p>"#,
    )
    .unwrap();
    assert!(context.contains("{broken recipe data}"));
    assert!(context.contains("1 medium onion"));
    let error = br#"{"error":{"message":"Model does not support URL context: AIzaSecretKey"}}"#;
    let reason = provider::failure_reason(error).unwrap();
    assert!(reason.contains("Model does not support URL context"));
    assert!(!reason.contains("AIzaSecretKey"));
    let error = br#"{"steps":[{"type":"url_context_result","result":[{"status":"paywall"}]}]}"#;
    assert_eq!(
        provider::failure_reason(error).unwrap(),
        "Gemini URL context: paywall"
    );
}

#[test]
fn editor_normalizes_old_units_embedded_units_and_times_but_not_exact_amounts() {
    let mut content = fields("Old synthetic recipe");
    content.prep_time = "1 hour 30 minutes".into();
    content.cook_time = "45 minutes".into();
    content.total_time = "30 min, plus proof".into();
    for unit in [
        "TB",
        "Tbsp",
        "tsp.",
        "Cup",
        "cup.",
        "pounds",
        "ounces",
        "teaspoons",
    ] {
        content.ingredients.push(recipe::Ingredient {
            amount: serde_json::from_str(r#"{"kind":"number","numerator":33,"denominator":100}"#)
                .unwrap(),
            unit: unit.into(),
            name: "synthetic ingredient".into(),
            prep_note: String::new(),
            optional: false,
            section: String::new(),
        });
    }
    for name in [
        "TB butter",
        "cup. flour",
        "orange juice",
        "cup-shaped pasta",
        "cup",
    ] {
        let mut row = content.ingredients[0].clone();
        row.unit.clear();
        row.name = name.into();
        content.ingredients.push(row);
    }
    let normalized = content
        .parse_editor(&vec![None; content.ingredients.len()])
        .unwrap();
    assert_eq!(
        normalized
            .ingredients
            .iter()
            .map(|r| r.unit.as_str())
            .collect::<Vec<_>>(),
        [
            "tbsp", "tbsp", "tsp", "cup", "cup", "lb", "oz", "tsp", "tbsp", "cup", "", "", ""
        ]
    );
    assert_eq!(normalized.ingredients[8].name, "butter");
    assert_eq!(normalized.ingredients[9].name, "flour");
    assert!(
        normalized
            .ingredients
            .iter()
            .all(|r| r.amount.text() == "33/100")
    );
    assert_eq!(normalized.prep_time, "1 hr 30 min");
    assert_eq!(normalized.cook_time, "45 min");
    assert_eq!(normalized.total_time, "30 min, plus proof");
}

#[test]
fn a1_service_migrates_views_without_rewriting_legacy_history_or_unchanged_restore() {
    use cookdex_core::{storage, sync_store};
    let root = Root::new();
    let directory = root.0.join("flutter-v1");
    std::fs::create_dir_all(&directory).unwrap();
    let path = directory.join("cookdex.sqlite3");
    let now = "2026-10-14T12:00:00Z";
    let mut first = Recipe::new(fields("Legacy range"), now).unwrap();
    first.schema_version = 1;
    first.content.ingredients.push(recipe::Ingredient {
        amount: recipe::Amount::Unspecified,
        unit: String::new(),
        name: "garlic".into(),
        prep_note: "6-7 cloves; minced".into(),
        optional: false,
        section: String::new(),
    });
    let mut second = Recipe::new(fields("Exact unchanged"), now).unwrap();
    second.schema_version = 1;
    second.content.ingredients.push(recipe::Ingredient {
        amount: recipe::Amount::parse_exact("33/100").unwrap(),
        unit: "cup".into(),
        name: "cream".into(),
        prep_note: String::new(),
        optional: false,
        section: String::new(),
    });
    let old_zip = backup::write(&[first.clone(), second.clone()]).unwrap();
    let mut db = storage::open(&path).unwrap();
    let book = storage::Book {
        recipes: vec![
            serde_json::to_value(&first).unwrap(),
            serde_json::to_value(&second).unwrap(),
        ],
        ..Default::default()
    };
    storage::save(&mut db, 0, &book, now).unwrap();
    let before = sync_store::export(&db).unwrap();
    drop(db);
    let service = Service::open(&root).unwrap();
    assert_eq!(service.snapshot().unwrap().summaries.len(), 2);
    let viewed = service.detail(&first.id).unwrap().unwrap();
    assert_eq!(viewed.schema_version, 2);
    assert_eq!(viewed.content, first.content);
    service
        .edit_shopping(
            1,
            ShoppingEdit::AddManual {
                text: "bread".into(),
            },
            &op(),
        )
        .unwrap();
    let preview = service.preview_restore(&old_zip, &op()).unwrap();
    assert_eq!(preview.report.skipped, 2);
    assert!(preview.report.conflicts.is_empty());
    service.restore(&preview, &op()).unwrap();
    let mut db = storage::open(&path).unwrap();
    assert_eq!(sync_store::export(&db).unwrap().events, before.events);
    let loaded = storage::load(&mut db).unwrap().book.recipes;
    assert_eq!(loaded.len(), book.recipes.len());
    assert!(loaded.iter().all(|r| book.recipes.contains(r)));
    drop(db);
    let cleanup = service.preview_cleanup().unwrap();
    assert_eq!(cleanup.changed, 1);
    service.cleanup(&cleanup, &op()).unwrap();
    let fixed = service.detail(&first.id).unwrap().unwrap();
    assert_eq!(fixed.content.ingredients[0].amount.text(), "6–7");
    assert_eq!(fixed.content.ingredients[0].unit, "clove");
    assert_eq!(fixed.content.ingredients[0].prep_note, "minced");
    assert_eq!(fixed.revision, first.revision + 1);
    assert_eq!(service.preview_cleanup().unwrap().changed, 0);
    let db = storage::open(&path).unwrap();
    let after = sync_store::export(&db).unwrap();
    assert_eq!(after.events.len(), before.events.len() + 1);
    assert!(before.events.iter().all(|e| after.events.contains(e)));
    assert_eq!(
        after
            .events
            .iter()
            .filter(|e| e.recipe_id == second.id.0)
            .count(),
        1
    );
    drop(db);
    let base = service.detail(&second.id).unwrap().unwrap();
    let mut edited = base.content.clone();
    edited.ingredients[0].amount = recipe::Amount::parse_new("1/2–1").unwrap();
    let generation = service.snapshot().unwrap().generation;
    service.save(generation, Some(base), edited, &op()).unwrap();
    assert_eq!(
        service.detail(&second.id).unwrap().unwrap().revision,
        second.revision + 1
    );
    assert_eq!(
        backup::read(&service.backup(&op()).unwrap()).unwrap().len(),
        2
    );
}

#[test]
fn library_final_500_recipe_batches_are_atomic_snapshotted_and_exact() {
    use cookdex_core::{storage, sync_store};
    use std::time::Instant;
    let root = Root::new();
    let service = Service::open(&root).unwrap();
    let mut recipes = Vec::new();
    for i in 0..500 {
        let mut r = fixture()[0].clone();
        r.id = RecipeId(format!("library-scale-{i:03}"));
        r.content.title = format!("Synthetic supper {i:03}");
        r.content.tags = vec!["Weeknight".into(), "weeknight".into(), "to remove".into()];
        r.content.ingredients[0].name = "parm".into();
        let mut second = r.content.ingredients[0].clone();
        second.section = "Topping".into();
        second.amount = recipe::Amount::parse_exact("3/4").unwrap();
        r.content.ingredients.push(second);
        let mut destination = r.content.ingredients[0].clone();
        destination.name = "parmesan".into();
        r.content.ingredients.push(destination);
        r.validate().unwrap();
        recipes.push(r);
    }
    let bytes = backup::write(&recipes).unwrap();
    service
        .restore(&service.preview_restore(&bytes, &op()).unwrap(), &op())
        .unwrap();
    let db = storage::open(&root.0.join("flutter-v1/cookdex.sqlite3")).unwrap();
    for (label, tags, source, target) in [
        ("ingredient rename", false, "parm", Some("aged parmesan")),
        ("ingredient merge", false, "parm", Some("parmesan")),
        ("tag merge", true, "Weeknight", Some("weeknight")),
        ("tag removal", true, "to remove", None),
        ("tag addition", true, "", Some("new tag")),
    ] {
        let before: Vec<_> = recipes
            .iter()
            .map(|r| service.detail(&r.id).unwrap().unwrap())
            .collect();
        let initial = service.snapshot().unwrap();
        let events = sync_store::export(&db).unwrap().events.len();
        let subscription = service.subscribe().unwrap();
        let started = Instant::now();
        let (after, undo) = if source.is_empty() {
            service.add_library_tag(
                initial.generation,
                &recipes.iter().map(|r| r.id.clone()).collect::<Vec<_>>(),
                target.unwrap(),
                &op(),
            )
        } else {
            service.change_library_names(initial.generation, tags, &[source.into()], target, &op())
        }
        .unwrap();
        let edit_ms = started.elapsed().as_secs_f64() * 1000.0;
        assert_eq!(after.generation, initial.generation + 1);
        assert_eq!(undo.count(), 500);
        let change = subscription.receiver.recv().unwrap();
        assert_eq!(change.changed.len(), 500);
        assert!(change.deleted.is_empty());
        assert!(subscription.receiver.try_recv().is_err());
        assert_eq!(sync_store::export(&db).unwrap().events.len(), events + 500);
        let snapshot = service.rolling_snapshots().unwrap().0.pop().unwrap();
        assert_eq!(snapshot.reason, "before_library");
        assert_eq!(
            backup::read(&service.rolling_snapshot_bytes(&snapshot.id).unwrap()).unwrap(),
            before
        );
        for r in &before {
            let mut expected = r.clone();
            expected.revision += 1;
            if source.is_empty() {
                expected.content.tags.push(target.unwrap().into());
            } else if tags {
                expected.content.tags = match target {
                    Some(_) => vec!["weeknight".into(), "to remove".into()],
                    None => vec!["Weeknight".into(), "weeknight".into()],
                };
            } else {
                for row in &mut expected.content.ingredients {
                    if row.name == source {
                        row.name = target.unwrap().into();
                    }
                }
            }
            assert_eq!(service.detail(&r.id).unwrap().unwrap(), expected);
        }
        let before_undo = backup::read(&service.backup(&op()).unwrap()).unwrap();
        let started = Instant::now();
        let restored = service
            .undo_library_names(after.generation, &undo, &op())
            .unwrap();
        let undo_ms = started.elapsed().as_secs_f64() * 1000.0;
        assert_eq!(restored.generation, after.generation + 1);
        assert_eq!(subscription.receiver.recv().unwrap().changed.len(), 500);
        assert!(subscription.receiver.try_recv().is_err());
        let snapshot = service.rolling_snapshots().unwrap().0.pop().unwrap();
        assert_eq!(
            backup::read(&service.rolling_snapshot_bytes(&snapshot.id).unwrap()).unwrap(),
            before_undo
        );
        for r in &before {
            let mut expected = r.clone();
            expected.revision += 2;
            assert_eq!(service.detail(&r.id).unwrap().unwrap(), expected);
        }
        println!("LIBRARY_500 {label}: snapshot+batch={edit_ms:.3}ms snapshot+undo={undo_ms:.3}ms");
    }
}

#[test]
fn library_final_validation_and_stale_undo_never_partially_commit() {
    let root = Root::new();
    let service = Service::open(&root).unwrap();
    let before = seed(&service);
    let source = before.summaries[0].ingredients[0].clone();
    let ids: Vec<_> = before.summaries.iter().map(|r| r.id.clone()).collect();
    // A missing final member and invalid names are rejected after earlier staged work.
    let mut missing_ids = ids.clone();
    missing_ids.push(RecipeId("missing-recipe".into()));
    assert!(
        service
            .add_library_tag(before.generation, &missing_ids, "new tag", &op())
            .is_err()
    );
    assert!(
        service
            .change_library_names(
                before.generation,
                false,
                &[source.clone(), "missing name".into()],
                Some("renamed"),
                &op()
            )
            .is_err()
    );
    assert!(
        service
            .add_library_tag(before.generation, &ids, &"x".repeat(10000), &op())
            .is_err()
    );
    assert_eq!(service.snapshot().unwrap(), before);
    let (after, undo) = service
        .change_library_names(before.generation, false, &[source], Some("renamed"), &op())
        .unwrap();
    let base = service.detail(&ids[0]).unwrap().unwrap();
    let mut content = base.content.clone();
    content.notes = "A newer edit".into();
    service
        .save(after.generation, Some(base), content, &op())
        .unwrap();
    let newer = service.snapshot().unwrap();
    assert!(
        service
            .undo_library_names(newer.generation, &undo, &op())
            .is_err()
    );
    assert_eq!(service.snapshot().unwrap(), newer);
}

#[test]
fn library_final_destination_aisle_wins_and_undo_checks_local_aisle_edits() {
    use cookdex_core::{shopping_categories::Setup, storage};
    let root = Root::new();
    let service = Service::open(&root).unwrap();
    let mut r = fixture()[0].clone();
    r.content.ingredients[0].name = "parm".into();
    let mut setup = Setup::default();
    setup.remember("parm", "spices").unwrap();
    setup.remember("parmesan", "dairy").unwrap();
    let bytes = backup::write_with_setup(&[r.clone()], Some(&setup)).unwrap();
    let initial = service
        .restore(&service.preview_restore(&bytes, &op()).unwrap(), &op())
        .unwrap();
    let (after, undo) = service
        .change_library_names(
            initial.generation,
            false,
            &["parm".into()],
            Some("parmesan"),
            &op(),
        )
        .unwrap();
    let mut db = storage::open(&root.0.join("flutter-v1/cookdex.sqlite3")).unwrap();
    assert_eq!(storage::load(&mut db).unwrap().book.shopping_setup, setup);
    let restored = service
        .undo_library_names(after.generation, &undo, &op())
        .unwrap();
    let (changed, undo) = service
        .change_library_names(
            restored.generation,
            false,
            &["parm".into()],
            Some("aged parmesan"),
            &op(),
        )
        .unwrap();
    let current = service.detail(&r.id).unwrap().unwrap();
    let mut changed_setup = storage::load(&mut db).unwrap().book.shopping_setup;
    changed_setup.remember("aged parmesan", "dairy").unwrap();
    let bytes = backup::write_with_setup(&[current.clone()], Some(&changed_setup)).unwrap();
    let newer = service
        .restore(&service.preview_restore(&bytes, &op()).unwrap(), &op())
        .unwrap();
    assert!(newer.generation > changed.generation);
    assert!(
        service
            .undo_library_names(newer.generation, &undo, &op())
            .is_err()
    );
    assert_eq!(service.detail(&r.id).unwrap().unwrap(), current);
    assert_eq!(
        storage::load(&mut db).unwrap().book.shopping_setup,
        changed_setup
    );
}
