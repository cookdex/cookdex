use cookdex_core::{
    adapters::AppPaths,
    backup,
    recipe::{Amount, Ingredient, Recipe},
    services::{Error, Operation, Service, ShoppingEdit as Edit},
    shopping_categories::{INGREDIENTS, Setup, normalize},
    storage,
};
use std::path::PathBuf;
struct Root(PathBuf);
impl Root {
    fn new() -> Self {
        Self(std::env::temp_dir().join(format!("cookdex-a3-{}", uuid::Uuid::new_v4())))
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
fn edit(s: &Service, e: Edit) -> cookdex_core::services::Snapshot {
    s.edit_shopping(s.snapshot().unwrap().generation, e, &op())
        .unwrap()
        .snapshot
}
fn add(s: &Service, name: &str) -> String {
    edit(s, Edit::AddManual { text: name.into() })
        .shopping
        .last()
        .unwrap()
        .id
        .clone()
}
fn recipe() -> Recipe {
    let v: serde_json::Value =
        serde_json::from_str(include_str!("../../../../tests/fixtures/corpus.json")).unwrap();
    Recipe::from_json(&serde_json::to_vec(&v["recipes"][0]).unwrap()).unwrap()
}
#[test]
fn offline_vocabulary_and_owner_examples() {
    assert!(
        INGREDIENTS
            .iter()
            .map(|(_, v)| v.split('|').count())
            .sum::<usize>()
            > 300
    );
    let s = Setup::default();
    for (name, category) in [
        ("large white onions", "produce"),
        ("onion powder", "spices"),
        ("chicken broth", "pantry"),
        ("peanut butter", "pantry"),
        ("2 cups fresh organic green onions, chopped", "produce"),
        ("Hamb.", "meat"),
        ("hamburger", "meat"),
        ("gr. pepper", "produce"),
        ("Crisco", "pantry"),
        ("Velveeta", "dairy"),
        ("Rotel", "canned"),
        ("Bisquick", "pantry"),
        ("Sazón", "spices"),
        ("catsup", "pantry"),
        ("ketchup", "pantry"),
        ("chiles", "produce"),
        ("chili powder", "spices"),
        ("scallions", "produce"),
        ("boneless chicken breasts", "meat"),
        ("low-sodium chicken broth", "pantry"),
        ("2% milk", "dairy"),
        ("frozen peas", "frozen"),
        ("canned tomatoes", "canned"),
        ("dried apricots", "pantry"),
        ("dried thyme", "spices"),
        ("white onions (finely chopped)", "produce"),
        ("freshly chopped carrots", "produce"),
        ("onoin", "other"),
        ("Cloves", "spices"),
        ("brussels sprouts", "produce"),
        ("ice cream", "frozen"),
        ("cream of mushroom soup", "canned"),
        ("coconut milk", "pantry"),
        ("ground coriander", "spices"),
        ("water", "beverages"),
    ] {
        assert_eq!(s.classify(name), category, "{name}");
    }
}
#[test]
fn remembered_names_share_normalization_longest_phrase_and_typos() {
    let mut s = Setup::default();
    s.remember("white onions", "frozen").unwrap();
    assert_eq!(s.classify("2 large white onions, diced"), "frozen");
    s.remember("onion", "pantry").unwrap();
    assert_eq!(s.classify("onion powder"), "spices");
    s.remember("onoin", "produce").unwrap();
    assert_eq!(s.classify("large onoin"), "produce");
    assert_eq!(s.classify("onioon"), "other");
    s.remember("scallion", "frozen").unwrap();
    assert_eq!(s.classify("green onions"), "frozen");
    for key in s.placements.keys() {
        assert_eq!(normalize(key), *key);
    }
    assert_eq!(s.classify("canned onion"), "canned");
    s.remember("canned onion", "produce").unwrap();
    assert_eq!(s.classify("canned onions"), "produce");
}
#[test]
fn order_check_undo_move_and_restart() {
    let root = Root::new();
    let s = Service::open(&root).unwrap();
    let a = add(&s, "apple");
    let b = add(&s, "banana");
    let c = add(&s, "carrot");
    edit(
        &s,
        Edit::ReorderItems {
            category_id: "produce".into(),
            ids: vec![c.clone(), a.clone(), b.clone()],
        },
    );
    let checked = s
        .edit_shopping(
            s.snapshot().unwrap().generation,
            Edit::Check {
                ids: vec![a.clone()],
                checked: true,
            },
            &op(),
        )
        .unwrap();
    let d = add(&s, "pear");
    s.undo_shopping(s.snapshot().unwrap().generation, &checked.undo, &op())
        .unwrap();
    assert_eq!(
        s.snapshot()
            .unwrap()
            .shopping
            .iter()
            .map(|i| i.id.clone())
            .collect::<Vec<_>>(),
        vec![c, a.clone(), b, d]
    );
    edit(
        &s,
        Edit::Move {
            before_id: None,
            id: a.clone(),
            category_id: "pantry".into(),
        },
    );
    let moved = s.snapshot().unwrap().shopping.last().unwrap().clone();
    assert_eq!(moved.id, a);
    assert_eq!(moved.category_id, "pantry");
    drop(s);
    let s = Service::open(&root).unwrap();
    let x = add(&s, "large apples");
    assert_eq!(
        s.snapshot()
            .unwrap()
            .shopping
            .iter()
            .find(|i| i.id == x)
            .unwrap()
            .category_id,
        "pantry"
    );
}
#[test]
fn categories_validate_delete_and_persist() {
    let root = Root::new();
    let s = Service::open(&root).unwrap();
    let added = edit(
        &s,
        Edit::AddCategory {
            name: "My aisle".into(),
        },
    );
    let id = added.shopping_categories.last().unwrap().id.clone();
    let item = add(&s, "quirky food");
    edit(
        &s,
        Edit::Move {
            before_id: None,
            id: item.clone(),
            category_id: id.clone(),
        },
    );
    edit(
        &s,
        Edit::RenameCategory {
            id: id.clone(),
            name: "First aisle".into(),
        },
    );
    let mut ids = s
        .snapshot()
        .unwrap()
        .shopping_categories
        .iter()
        .map(|c| c.id.clone())
        .collect::<Vec<_>>();
    ids.reverse();
    edit(&s, Edit::ReorderCategories { ids: ids.clone() });
    assert_eq!(s.snapshot().unwrap().shopping_categories[0].id, id);
    let generation = s.snapshot().unwrap().generation;
    for e in [
        Edit::AddCategory {
            name: "Produce".into(),
        },
        Edit::RenameCategory {
            id: id.clone(),
            name: " ".into(),
        },
        Edit::DeleteCategory { id: "other".into() },
        Edit::ReorderCategories {
            ids: vec!["other".into()],
        },
    ] {
        assert!(s.edit_shopping(generation, e, &op()).is_err());
        assert_eq!(s.snapshot().unwrap().generation, generation);
    }
    edit(&s, Edit::DeleteCategory { id: id.clone() });
    assert_eq!(s.snapshot().unwrap().shopping[0].category_id, "other");
    let x = add(&s, "large quirky food");
    assert_eq!(
        s.snapshot()
            .unwrap()
            .shopping
            .iter()
            .find(|i| i.id == x)
            .unwrap()
            .category_id,
        "other"
    );
    drop(s);
    let s = Service::open(&root).unwrap();
    assert!(
        !s.snapshot()
            .unwrap()
            .shopping_categories
            .iter()
            .any(|c| c.id == id)
    );
}
#[test]
fn recipe_water_ice_skipped_manual_allowed_and_ranges_sources_unchanged() {
    let root = Root::new();
    let s = Service::open(&root).unwrap();
    let mut r = recipe();
    r.content.ingredients = [
        "water",
        "ice",
        "cold water",
        "ice cubes",
        "chicken broth",
        "onion powder",
        "peanut butter",
    ]
    .into_iter()
    .map(|name| Ingredient {
        amount: Amount::parse_new("1–2").unwrap(),
        unit: "cup".into(),
        name: name.into(),
        prep_note: String::new(),
        optional: false,
        section: String::new(),
    })
    .collect();
    let restored = s
        .restore(
            &s.preview_restore(&backup::write(&[r.clone()]).unwrap(), &op())
                .unwrap(),
            &op(),
        )
        .unwrap();
    let first = s
        .add_shopping(restored.generation, &r.id, &[0, 1, 2, 3, 4, 5, 6], &op())
        .unwrap();
    assert_eq!(first.snapshot.shopping.len(), 3);
    let id = first.snapshot.shopping[0].id.clone();
    edit(
        &s,
        Edit::Move {
            before_id: None,
            id: id.clone(),
            category_id: "other".into(),
        },
    );
    let again = s
        .add_shopping(s.snapshot().unwrap().generation, &r.id, &[4, 5, 6], &op())
        .unwrap();
    let item = again.snapshot.shopping.iter().find(|i| i.id == id).unwrap();
    assert_eq!(item.quantity_text(), "2–4 cups");
    assert_eq!(item.category_id, "other");
    assert_eq!(item.contributors, vec![r.id]);
    add(&s, "water");
    add(&s, "ice");
    assert_eq!(s.snapshot().unwrap().shopping.len(), 5);
}
#[test]
fn backup_setup_roundtrip_legacy_and_stale_preview() {
    let source = Root::new();
    let s = Service::open(&source).unwrap();
    let id = add(&s, "white onion");
    edit(
        &s,
        Edit::AddCategory {
            name: "Farm stand".into(),
        },
    );
    let category = s
        .snapshot()
        .unwrap()
        .shopping_categories
        .last()
        .unwrap()
        .id
        .clone();
    edit(
        &s,
        Edit::Move {
            before_id: None,
            id,
            category_id: category.clone(),
        },
    );
    let mut order = s
        .snapshot()
        .unwrap()
        .shopping_categories
        .iter()
        .map(|c| c.id.clone())
        .collect::<Vec<_>>();
    order.reverse();
    edit(&s, Edit::ReorderCategories { ids: order });
    let bytes = s.backup(&op()).unwrap();
    let (recipes, setup) = backup::read_with_setup(&bytes).unwrap();
    assert!(recipes.is_empty());
    let setup = setup.unwrap();
    assert_eq!(setup.classify("large white onions"), category);
    let target = Root::new();
    let t = Service::open(&target).unwrap();
    let preview = t.preview_restore(&bytes, &op()).unwrap();
    assert!(preview.report.shopping_setup);
    t.restore(&preview, &op()).unwrap();
    assert_eq!(
        t.snapshot().unwrap().shopping_categories,
        s.snapshot().unwrap().shopping_categories
    );
    assert!(t.snapshot().unwrap().shopping.is_empty());
    let x = add(&t, "large white onion");
    assert_eq!(
        t.snapshot()
            .unwrap()
            .shopping
            .iter()
            .find(|i| i.id == x)
            .unwrap()
            .category_id,
        category
    );
    let old = t
        .preview_restore(&backup::write(&[recipe()]).unwrap(), &op())
        .unwrap();
    assert!(!old.report.shopping_setup);
    t.restore(&old, &op()).unwrap();
    assert_eq!(
        t.snapshot().unwrap().shopping_categories,
        s.snapshot().unwrap().shopping_categories
    );
    let stale = t.preview_restore(&bytes, &op()).unwrap();
    add(&t, "other item");
    assert_eq!(t.restore(&stale, &op()).unwrap_err(), Error::StaleWrite);
}
#[test]
fn pre_a3_local_rows_get_categories_without_recipe_rewrite() {
    let root = Root::new();
    let session = cookdex_core::session::Session::open(&root).unwrap();
    let r = recipe();
    let raw = serde_json::to_value(&r).unwrap();
    let mut book = storage::Book::default();
    book.recipes = vec![raw.clone()];
    book.shopping = vec![
        serde_json::json!({"id":"old","name":"onion","measures":[],"contributors":[],"checked":true}),
    ];
    session.save(0, &book, "2026-10-14T00:00:00Z").unwrap();
    drop(session);
    let s = Service::open(&root).unwrap();
    assert_eq!(s.snapshot().unwrap().shopping[0].category_id, "produce");
    assert!(s.snapshot().unwrap().shopping[0].checked);
    assert_eq!(
        serde_json::to_value(s.detail(&r.id).unwrap().unwrap()).unwrap(),
        raw
    );
}
#[test]
fn malformed_setup_is_rejected_before_restore() {
    let mut setup = Setup::default();
    setup.placements.insert("onion".into(), "missing".into());
    assert!(backup::write_with_setup(&[], Some(&setup)).is_err());
    let mut setup = Setup::default();
    setup.categories.push(setup.categories[0].clone());
    assert!(setup.validate().is_err());
    let mut setup = Setup::default();
    setup
        .placements
        .insert("Large Onions".into(), "produce".into());
    assert!(setup.validate().is_err());
}

#[test]
fn recipe_sync_never_transfers_categories_placements_or_shopping_order() {
    use cookdex_core::sync_store;
    let mut a = storage::open(std::path::Path::new(":memory:")).unwrap();
    let mut b = storage::open(std::path::Path::new(":memory:")).unwrap();
    let mut book = storage::Book::default();
    book.recipes = vec![serde_json::to_value(recipe()).unwrap()];
    book.shopping_setup.categories.reverse();
    book.shopping_setup.remember("onion", "frozen").unwrap();
    book.shopping = vec![
        serde_json::to_value(cookdex_core::shopping::Item::manual("onion".into()).unwrap())
            .unwrap(),
    ];
    storage::save(&mut a, 0, &book, "2026-10-14T00:00:00Z").unwrap();
    sync_store::merge(
        &mut b,
        sync_store::export(&a).unwrap(),
        "2026-10-14T00:00:00Z",
    )
    .unwrap();
    let received = storage::load(&mut b).unwrap().book;
    assert_eq!(received.recipes, book.recipes);
    assert_eq!(received.shopping_setup, Setup::default());
    assert!(received.shopping.is_empty());
    assert_eq!(
        storage::load(&mut a).unwrap().book.shopping_setup,
        book.shopping_setup
    );
}

#[test]
fn reviewer_plural_storage_notes_and_quantity_alias_regressions() {
    let mut setup = Setup::default();
    for (singular, plural) in [
        ("peach", "peaches"),
        ("radish", "radishes"),
        ("squash", "squashes"),
        ("mango", "mangoes"),
        ("hamburger", "hamburgers"),
        ("catsup", "catsups"),
    ] {
        assert_eq!(normalize(singular), normalize(plural));
        assert_ne!(setup.classify(plural), "other");
        setup.remember(singular, "other").unwrap();
        assert_eq!(setup.classify(plural), "other");
    }
    for (name, category) in [
        ("peas (frozen)", "frozen"),
        ("tomatoes, canned", "canned"),
        ("apricots [dried]", "pantry"),
        ("thyme, dried", "spices"),
    ] {
        assert_eq!(Setup::default().classify(name), category);
    }
    for name in [
        "2 c. onions",
        "1 T. onions",
        "2 tbs onions",
        "2 TB onions",
        "2 cups onions",
    ] {
        let mut setup = Setup::default();
        setup.remember(name, "frozen").unwrap();
        assert_eq!(setup.classify("large onion"), "frozen");
    }
    assert_eq!(normalize("2 cloves garlic"), "garlic");
    assert_eq!(Setup::default().classify("cloves"), "spices");
    for name in ["ice water", "room temperature water", "lukewarm water"] {
        assert!(cookdex_core::shopping_categories::recipe_omitted(name));
    }
}
#[test]
fn cross_category_move_inserts_at_drop_position_and_remembers() {
    let root = Root::new();
    let s = Service::open(&root).unwrap();
    let onion = add(&s, "white onion");
    let rice = add(&s, "rice");
    let pasta = add(&s, "pasta");
    edit(
        &s,
        Edit::Move {
            id: onion.clone(),
            category_id: "pantry".into(),
            before_id: Some(pasta.clone()),
        },
    );
    assert_eq!(
        s.snapshot()
            .unwrap()
            .shopping
            .iter()
            .map(|i| i.id.clone())
            .collect::<Vec<_>>(),
        vec![rice, onion, pasta]
    );
    add(&s, "large white onion");
    assert_eq!(
        s.snapshot().unwrap().shopping.last().unwrap().category_id,
        "pantry"
    );
}

#[test]
fn ingredient_names_are_not_consumed_as_quantity_words_or_units() {
    for name in ["clove", "cloves", "1 clove", "2 cloves"] {
        let mut setup = Setup::default();
        assert_eq!(setup.classify(name), "spices");
        setup.remember(name, "pantry").unwrap();
        assert_eq!(setup.classify("cloves"), "pantry");
    }
    for name in [
        "half and half",
        "half-and-half",
        "half & half",
        "1 cup half and half",
    ] {
        let mut setup = Setup::default();
        assert_eq!(setup.classify(name), "dairy");
        setup.remember(name, "pantry").unwrap();
        assert_eq!(setup.classify("half and half"), "pantry");
    }
    assert_eq!(Setup::default().classify("foo and bar"), "other");
    assert_eq!(normalize("2 cloves fresh garlic"), "garlic");
    for (_, words) in INGREDIENTS {
        for word in words.split('|') {
            let key = normalize(word);
            assert!(!key.is_empty() && key != "and", "{word}");
            assert_eq!(normalize(&key), key, "{word}");
        }
    }
}
