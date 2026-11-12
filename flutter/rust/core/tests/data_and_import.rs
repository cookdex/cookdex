use cookdex_core::{
    backup,
    recipe::{self, Amount, Recipe},
    storage,
    sync_store::{self, phone_backup},
};
use rusqlite::Connection;
use serde_json::json;

fn book() -> storage::Book {
    serde_json::from_str(include_str!("native-fixture.json")).unwrap()
}
fn db() -> Connection {
    storage::open(std::path::Path::new(":memory:")).unwrap()
}
#[test]
fn arbitrary_source_survives_zip_and_text_and_never_consumes_notes_or_ingredient_sections() {
    let mut recipe = Recipe::from_json(&serde_json::to_vec(&book().recipes[0]).unwrap()).unwrap();
    recipe.content.notes = "a".repeat(20000);
    recipe.content.ingredients[0].section = "Source: real ingredient section".into();
    for source in [
        "",
        "https://example.org/recipe",
        "Salt Fat Acid Heat, p. 112",
        "Grandma’s recipe box",
        "javascript:alert(1)",
        "页 | é\nfamily \\ book",
        &"½".repeat(2000),
    ] {
        recipe.content.source = source.into();
        let zip = backup::write(std::slice::from_ref(&recipe)).unwrap();
        assert_eq!(backup::read(&zip).unwrap(), [recipe.clone()]);
        let written = recipe::text::export_recipe(&recipe).unwrap();
        let restored = recipe::text::import_text(&written, &recipe.created_at).unwrap();
        assert_eq!(restored.candidates[0].recipe.content, recipe.content);
    }
}
#[test]
fn mixed_and_range_amounts_work_in_lines_exact_text_and_written_fields() {
    for (raw, canonical) in [
        ("1 and 1/2", "1 1/2"),
        ("1 & 1/2", "1 1/2"),
        ("1-1/2", "1 1/2"),
        ("1 and ½", "1 1/2"),
        ("1 & ½", "1 1/2"),
        ("1-½", "1 1/2"),
        ("2 and ⅚", "2 5/6"),
        ("2-⅖", "2 2/5"),
        ("2-3", "2–3"),
        ("1-2", "1–2"),
        ("1/2-3/4", "1/2–3/4"),
        ("½-¾", "1/2–3/4"),
        ("1 to 1 1/2", "1–1 1/2"),
        ("1 to 1½", "1–1 1/2"),
        ("1-3/2", "1–1 1/2"),
    ] {
        let amount = Amount::parse_new(raw).unwrap();
        assert_eq!(amount.text(), canonical, "{raw}");
        assert_eq!(Amount::parse_exact(raw).unwrap(), amount);
        let line = format!("{raw} cups oats");
        let ingredient = recipe::paste::parse_ingredients(&line, "")
            .unwrap()
            .remove(0);
        assert_eq!(ingredient.ingredient.amount, amount, "{line}");
        assert_eq!(ingredient.ingredient.name, "oats");
        assert!(ingredient.ingredient.prep_note.is_empty());
    }
}
#[test]
fn fresh_phone_and_original_merge_disjoint_edits_conflicts_and_deletions() {
    let mut old = db();
    let mut peer = db();
    let mut new = db();
    let mut initial = book();
    for n in 1..4 {
        let mut recipe = initial.recipes[0].clone();
        recipe["id"] = json!(format!("other-{n}"));
        initial.recipes.push(recipe);
    }
    initial.shopping = vec![
        serde_json::to_value(cookdex_core::shopping::Item::manual("Lemons".into()).unwrap())
            .unwrap(),
    ];
    storage::save(&mut old, 0, &initial, "initial").unwrap();
    let push = |a: &Connection, b: &mut Connection| {
        sync_store::merge(b, sync_store::export(a).unwrap(), "sync").unwrap()
    };
    let edit = |db: &mut Connection, index: &str, text: &str| {
        let mut state = storage::load(db).unwrap();
        state
            .book
            .recipes
            .iter_mut()
            .find(|r| r["id"] == index)
            .unwrap()["notes"] = json!(text);
        storage::save(db, state.generation, &state.book, "edit").unwrap();
    };
    push(&old, &mut peer);
    let shared = initial.recipes[0]["id"].as_str().unwrap();
    edit(&mut old, shared, "Old branch");
    edit(&mut peer, shared, "Peer branch");
    push(&peer, &mut old);
    let conflict_before = sync_store::conflicts(&old).unwrap();
    assert_eq!(conflict_before.as_array().unwrap().len(), 1);
    old.execute(
        "INSERT INTO local VALUES ('syncConfig','\"private pairing sentinel\"')",
        [],
    )
    .unwrap();
    let archive = phone_backup::encode(&mut old).unwrap();
    phone_backup::restore(&mut new, &archive).unwrap();
    assert!(phone_backup::restore(&mut new, &archive).is_err());
    let device_id = |db: &Connection| {
        db.query_row("SELECT device_id FROM state", [], |r| r.get::<_, String>(0))
            .unwrap()
    };
    assert_ne!(device_id(&new), device_id(&old));
    assert_eq!(
        new.query_row(
            "SELECT COUNT(*) FROM local WHERE key IN ('previous','syncConfig')",
            [],
            |r| r.get::<_, u32>(0)
        )
        .unwrap(),
        0
    );
    assert_eq!(sync_store::conflicts(&new).unwrap(), conflict_before);
    assert_eq!(
        storage::load(&mut new).unwrap().book,
        storage::load(&mut old).unwrap().book
    );
    edit(&mut new, "other-1", "New phone edit");
    edit(&mut old, "other-2", "Old phone edit");
    let mut state = storage::load(&mut peer).unwrap();
    state.book.recipes.retain(|r| r["id"] != "other-3");
    storage::save(&mut peer, state.generation, &state.book, "deleted").unwrap();
    push(&old, &mut peer);
    push(&peer, &mut new);
    push(&new, &mut old);
    push(&old, &mut peer);
    let final_state = storage::load(&mut new).unwrap().book;
    assert_eq!(final_state.recipes.len(), 3);
    assert!(
        final_state
            .recipes
            .iter()
            .any(|r| r["notes"] == "New phone edit")
    );
    assert!(
        final_state
            .recipes
            .iter()
            .any(|r| r["notes"] == "Old phone edit")
    );
    assert_eq!(
        storage::load(&mut old).unwrap().book.recipes,
        final_state.recipes
    );
    let peer_recipes = storage::load(&mut peer).unwrap().book.recipes;
    assert_eq!(peer_recipes.len(), final_state.recipes.len());
    // During a genuine pre-existing conflict each peer keeps its local visible
    // version. Both still have the exact same two alternatives and other recipes.
    for r in final_state.recipes.iter().filter(|r| r["id"] != shared) {
        assert!(peer_recipes.contains(r));
    }
    assert_eq!(sync_store::conflicts(&new).unwrap(), conflict_before);
    assert_eq!(sync_store::conflicts(&peer).unwrap(), conflict_before);
}

#[test]
fn rejected_phone_archive_leaves_fresh_database_usable_for_retry() {
    use flate2::{Compression, read::GzDecoder, write::GzEncoder};
    use std::io::{Read, Write};
    let mut old = db();
    let mut new = db();
    storage::save(&mut old, 0, &book(), "initial").unwrap();
    let good = phone_backup::encode(&mut old).unwrap();
    let mut raw = Vec::new();
    GzDecoder::new(good.as_slice())
        .read_to_end(&mut raw)
        .unwrap();
    let mut library: serde_json::Value = serde_json::from_slice(&raw).unwrap();
    let selected = library["selected"]
        .as_object_mut()
        .unwrap()
        .values_mut()
        .next()
        .unwrap();
    *selected = json!("unrelated revision");
    let mut encoded = GzEncoder::new(vec![], Compression::default());
    encoded
        .write_all(&serde_json::to_vec(&library).unwrap())
        .unwrap();
    for damaged in [encoded.finish().unwrap(), good[..good.len() / 2].to_vec()] {
        assert!(phone_backup::restore(&mut new, &damaged).is_err());
        assert!(sync_store::export(&new).unwrap().events.is_empty());
        assert_eq!(storage::load(&mut new).unwrap().generation, 0);
    }
    phone_backup::restore(&mut new, &good).unwrap();
    assert_eq!(
        storage::load(&mut new).unwrap().book,
        storage::load(&mut old).unwrap().book
    );
}
