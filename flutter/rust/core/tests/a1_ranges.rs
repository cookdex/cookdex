use cookdex_core::{
    backup, provider,
    recipe::{self, Amount, Ingredient, Recipe},
    shopping, storage, sync_store,
};
use serde_json::{Value, json};
const NOW: &str = "2026-10-14T12:00:00Z";
fn legacy() -> Value {
    serde_json::from_str::<Value>(include_str!("../../../../tests/fixtures/corpus.json")).unwrap()
        ["recipes"][0]
        .clone()
}
fn recipe() -> Recipe {
    Recipe::from_json(&serde_json::to_vec(&legacy()).unwrap()).unwrap()
}
fn row(amount: &str, unit: &str) -> Ingredient {
    Ingredient {
        amount: Amount::parse_new(amount).unwrap(),
        unit: unit.into(),
        name: "garlic".into(),
        prep_note: String::new(),
        optional: false,
        section: String::new(),
    }
}
#[test]
fn exact_endpoints_separators_snapping_and_invalid_input() {
    for s in ["6-7", "6 - 7", "6 to 7", "6–7", "6 TO 7"] {
        assert_eq!(Amount::parse_new(s).unwrap().text(), "6–7");
    }
    for (s, expected) in [
        ("1/2–1", "1/2–1"),
        ("1 1/2 - 2", "1 1/2–2"),
        ("½–1½", "1/2–1 1/2"),
        ("0.33–0.667", "1/3–2/3"),
        ("33/100–67/100", "33/100–67/100"),
        ("2-2", "2"),
        ("1/2 to 2/4", "1/2"),
        ("0.999–1.001", "1"),
    ] {
        assert_eq!(Amount::parse_new(s).unwrap().text(), expected, "{s}");
    }
    for s in ["7–6", "1.001–0.999", "2–1 1/2"] {
        assert!(
            Amount::parse_new(s)
                .unwrap_err()
                .to_string()
                .contains("first amount")
        );
    }
    for s in [
        "1-inch",
        "9x13-inch",
        "1–",
        "–2",
        "1–2–3",
        "1 to taste",
        "0–1",
        "1/0–2",
        "1–9007199254740992",
        "1–-2",
    ] {
        assert!(Amount::parse_new(s).is_err(), "{s}");
    }
    assert_eq!(row("1–2", "cup").text(), "1–2 cups garlic");
    assert_eq!(row("1/2–1", "cup").text(), "1/2–1 cup garlic");
}
#[test]
fn all_local_import_routes_accept_ranges_without_quantity_warnings() {
    for amount in ["6-7", "6 - 7", "6 to 7", "6–7", "1/2–1", "1 1/2–2"] {
        let expected = Amount::parse_new(amount).unwrap();
        let written = json!({"status":"ok","reason":"","title":"Garlic","description":"","servings":"","prepTime":"","cookTime":"","totalTime":"","source":"","notes":"","tags":[],"ingredients":[{"amount":amount,"unit":"cloves","name":"garlic","prepNote":"minced","optional":false,"section":""}],"steps":["Mix."]});
        let reply = serde_json::to_vec(&json!({"status":"completed","steps":[{"type":"model_output","content":[{"type":"text","text":written.to_string()}]}]})).unwrap();
        let (ai, warnings) = provider::validated_response(&reply).unwrap();
        assert!(warnings.is_empty(), "{warnings:?}");
        let text = recipe::text::export_recipe(&ai).unwrap();
        let own = recipe::text::import_text(&text, NOW)
            .unwrap()
            .candidates
            .remove(0)
            .recipe;
        let plain = recipe::paste::parse_recipe_input(
            &format!("Garlic\nIngredients:\n{amount} cloves garlic, minced\nSteps:\nMix."),
            NOW,
        )
        .unwrap()
        .candidates
        .remove(0)
        .recipe;
        let html = format!(
            "<script type=\"application/ld+json\">{}</script>",
            json!({"@type":"Recipe","name":"Garlic","recipeIngredient":[format!("{amount} cloves garlic, minced")],"recipeInstructions":["Mix."]})
        );
        let web = recipe::web::inspect_page(&html, "https://example.test/garlic", NOW)
            .unwrap()
            .imports
            .candidates
            .remove(0)
            .recipe;
        for r in [ai, own, plain, web] {
            assert_eq!(r.content.ingredients[0].amount, expected);
            assert_eq!(r.content.ingredients[0].unit, "clove");
            assert_eq!(r.content.ingredients[0].prep_note, "minced");
        }
    }
    for s in [
        "1-inch ginger",
        "9x13-inch pan",
        "6-7-inch strips",
        "7-6 cloves garlic",
    ] {
        let r = recipe::paste::parse_ingredients(s, "").unwrap().remove(0);
        assert_eq!(r.ingredient.amount, Amount::Unspecified);
        assert_eq!(r.ingredient.name, s);
    }
}
#[test]
fn save_cleanup_recovery_is_conservative_and_idempotent() {
    for (prep, unit, expected, remaining) in [
        ("6–7 cloves; minced", "", "6–7", "minced"),
        ("1/2 to 1 cups", "", "1/2–1", ""),
        ("1 1/2–2", "tsp", "1 1/2–2", ""),
        ("6-6 cloves", "", "6", ""),
    ] {
        let mut content = recipe().content;
        content.ingredients = vec![row("", unit)];
        content.ingredients[0].prep_note = prep.into();
        let fixed = content.parse_editor(&[None]).unwrap();
        assert_eq!(fixed.ingredients[0].amount.text(), expected);
        assert_eq!(fixed.ingredients[0].prep_note, remaining);
        assert_eq!(fixed.parse_editor(&[None]).unwrap(), fixed);
    }
    for prep in [
        "1-inch",
        "9x13-inch",
        "6-7 cloves minced",
        "6-7 or 8 cloves",
        "7–6 cloves",
        "6-7 handfuls",
        "about 6-7",
        "minced; 6-7 cloves",
    ] {
        let mut content = recipe().content;
        content.ingredients = vec![row("", "")];
        content.ingredients[0].prep_note = prep.into();
        assert_eq!(
            content.parse_editor(&[None]).unwrap().ingredients,
            content.ingredients,
            "{prep}"
        );
    }
    let mut content = recipe().content;
    content.ingredients = vec![row("2", "clove")];
    content.ingredients[0].prep_note = "6-7 cloves; minced".into();
    assert_eq!(
        content.parse_editor(&[None]).unwrap().ingredients,
        content.ingredients
    );
}
#[test]
fn shopping_adds_both_ends_with_exact_conversions_and_undo() {
    let mut r = recipe();
    r.content.ingredients = vec![row("6–7", "clove"), row("2", "clove")];
    let items = shopping::add(&[], &r, &[0, 1]).unwrap();
    assert_eq!(items.len(), 1);
    assert_eq!(items[0].quantity_text(), "8–9 cloves");
    r.content.ingredients = vec![row("1/2–1", "cup"), row("8–16", "tbsp")];
    let converted = shopping::add(&[], &r, &[0, 1]).unwrap();
    assert_eq!(converted[0].quantity_text(), "1–2 cups");
    assert_eq!(
        shopping::Undo::between(&[], &converted)
            .apply(&converted)
            .unwrap(),
        vec![]
    );
    r.content.ingredients = vec![
        row("9007199254740990–9007199254740991", "clove"),
        row("1", "clove"),
    ];
    assert!(shopping::add(&[], &r, &[0, 1]).is_err());
}
#[test]
fn migration_backups_sync_and_history_preserve_identity_and_exact_values() {
    let old = legacy();
    let migrated = recipe();
    let mut expected = old.clone();
    expected["schemaVersion"] = json!(2);
    assert_eq!(serde_json::to_value(&migrated).unwrap(), expected);
    // A genuine schema-1 ZIP, without passing through the migration reader first.
    let v1: Recipe = serde_json::from_value(old.clone()).unwrap();
    let old_zip = backup::write(&[v1]).unwrap();
    assert_eq!(backup::read(&old_zip).unwrap(), vec![migrated.clone()]);
    let mut a = storage::open(std::path::Path::new(":memory:")).unwrap();
    let mut b = storage::open(std::path::Path::new(":memory:")).unwrap();
    let mut book = storage::Book {
        recipes: vec![old],
        ..Default::default()
    };
    storage::save(&mut a, 0, &book, NOW).unwrap();
    let before = sync_store::export(&a).unwrap();
    let manifest_before = sync_store::manifest(&before).unwrap();
    storage::load(&mut a).unwrap();
    assert_eq!(
        sync_store::manifest(&sync_store::export(&a).unwrap()).unwrap(),
        manifest_before
    );
    sync_store::merge(&mut b, before.clone(), NOW).unwrap();
    let mut ranged = migrated;
    ranged.revision += 1;
    ranged.content.ingredients = vec![row("1/2–1", "cup")];
    book.recipes = vec![serde_json::to_value(&ranged).unwrap()];
    storage::save(&mut a, 1, &book, NOW).unwrap();
    let after = sync_store::export(&a).unwrap();
    assert!(after.events.iter().any(|e| e == &before.events[0]));
    sync_store::merge(&mut b, after.clone(), NOW).unwrap();
    let received = storage::load(&mut b).unwrap().book.recipes.remove(0);
    assert_eq!(
        Recipe::from_json(&serde_json::to_vec(&received).unwrap()).unwrap(),
        ranged
    );
    let zip = backup::write(&[ranged.clone()]).unwrap();
    assert_eq!(backup::read(&zip).unwrap(), vec![ranged]);
    let mut incompatible = after.clone();
    incompatible.version = 2;
    let prior = storage::load(&mut b).unwrap().generation;
    assert!(sync_store::merge(&mut b, incompatible, NOW).is_err());
    assert_eq!(storage::load(&mut b).unwrap().generation, prior);
}

#[test]
fn scaling_shopping_keeps_exact_totals_provenance_and_recipe() {
    let mut recipe = recipe();
    recipe.content.ingredients = vec![row("1/3", "cup"), row("2", "(14 oz) cans")];
    recipe.content.ingredients[1].name = "tomatoes".into();
    let before = recipe.clone();
    let items = shopping::add_scaled(&[], &recipe, &[0, 1], 1).unwrap();
    assert_eq!(items[0].quantity_text(), "2 tbsp + 2 tsp");
    assert_eq!(items[0].contributor_scales, ["×0.5"]);
    assert_eq!(items[1].quantity_text(), "1 (14 oz) cans");
    let again = shopping::add_scaled(&items, &recipe, &[0], 4).unwrap();
    assert_eq!(again[0].measures[0].amount.text(), "5/6");
    assert_eq!(again[0].contributor_scales, ["×0.5, ×2"]);
    assert_eq!(recipe, before);
    let reopened: Vec<shopping::Item> =
        serde_json::from_slice(&serde_json::to_vec(&again).unwrap()).unwrap();
    assert_eq!(reopened, again);
    let undone = shopping::Undo::between(&items, &again)
        .apply(&again)
        .unwrap();
    assert_eq!(undone, items);
}

#[test]
fn all_half_step_scales_survive_shopping_merge_and_storage() {
    let mut recipe = recipe();
    recipe.content.ingredients = vec![row("2", "")];
    let mut items = vec![];
    for scale in 1..=10 {
        items = shopping::add_scaled(&items, &recipe, &[0], scale).unwrap();
    }
    assert_eq!(items[0].measures[0].amount.text(), "55");
    assert_eq!(
        items[0].contributor_scales,
        ["×0.5, ×1, ×1.5, ×2, ×2.5, ×3, ×3.5, ×4, ×4.5, ×5"]
    );
    let reopened: Vec<shopping::Item> =
        serde_json::from_slice(&serde_json::to_vec(&items).unwrap()).unwrap();
    shopping::validate(&reopened).unwrap();
    assert_eq!(reopened, items);
}
