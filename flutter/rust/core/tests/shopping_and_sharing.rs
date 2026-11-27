use cookdex_core::{
    adapters::AppPaths,
    recipe::{self, Amount, Ingredient, Recipe, RecipeContent, RecipeId},
    services::{Error, Operation, Service, ShoppingEdit},
    shopping::{self, Item},
};
use std::{collections::HashSet, path::PathBuf};

fn recipe(id: &str, rows: &[(&str, &str, &str)]) -> Recipe {
    let mut recipe = Recipe::new(
        RecipeContent {
            title: id.into(),
            description: String::new(),
            servings: "4".into(),
            prep_time: String::new(),
            cook_time: String::new(),
            total_time: String::new(),
            source: String::new(),
            notes: String::new(),
            tags: vec![],
            ingredients: rows
                .iter()
                .map(|(name, amount, unit)| Ingredient {
                    name: (*name).into(),
                    amount: Amount::parse_exact(amount).unwrap(),
                    unit: (*unit).into(),
                    prep_note: String::new(),
                    section: String::new(),
                    optional: false,
                })
                .collect(),
            steps: vec!["Cook.".into()],
        },
        "2026-11-21T12:00:00Z",
    )
    .unwrap();
    recipe.id = RecipeId(id.into());
    recipe
}
#[test]
fn restocked_default_staples_use_aisles_and_preserve_custom_placements() {
    let mut setup = cookdex_core::shopping_categories::Setup::default();
    for (name, aisle) in [
        ("salt", "spices"),
        ("pepper", "spices"),
        ("oil", "pantry"),
        ("butter", "dairy"),
        ("flour", "pantry"),
        ("sugar", "pantry"),
        ("basic spices", "spices"),
    ] {
        assert_eq!(setup.classify(name), aisle, "{name}");
    }
    setup.remember("oil", "other").unwrap();
    assert_eq!(setup.classify("oil"), "other");
}
#[test]
fn shopping_table_single_combined_incompatible_ranges_and_units() {
    for (a, u, b, v, expected) in [
        ("1/3", "cup", "1/3", "cup", "2/3 cup"),
        ("1/2", "cup", "2", "tbsp", "1/2 cup + 2 tbsp"),
        ("2", "tbsp", "1/2", "cup", "1/2 cup + 2 tbsp"),
        ("800", "g", "400", "g", "1.2 kg"),
        ("250", "ml", "1", "l", "1.25 l"),
        ("1", "l", "250", "ml", "1.25 l"),
        ("1/3", "cup", "100", "g", "1/3 cup + 100 g"),
        ("1/3–1/2", "cup", "1/3–1/2", "cup", "2/3–1 cup"),
        ("800–900", "g", "400–500", "g", "1.2–1.4 kg"),
        ("1", "cup", "1", "tsp", "1 cup + 1 tsp"),
        ("1", "lb", "16", "oz", "2 lb"),
    ] {
        let r = recipe("dish", &[("cream", a, u), ("cream", b, v)]);
        let items = shopping::add_scaled(&[], &r, &[0, 1], 2).unwrap();
        assert_eq!(items.len(), 1, "{a} {u} + {b} {v}");
        assert_eq!(items[0].quantity_text(), expected, "{a} {u} + {b} {v}");
        let reopened: Vec<Item> =
            serde_json::from_slice(&serde_json::to_vec(&items).unwrap()).unwrap();
        shopping::validate(&reopened).unwrap();
        assert_eq!(reopened, items);
    }
    for (a, u, expected) in [
        ("1/3", "cup", "1/3 cup"),
        ("800", "g", "800 g"),
        ("250", "ml", "250 ml"),
        ("1", "tablespoon", "1 tbsp"),
    ] {
        let r = recipe("dish", &[("cream", a, u)]);
        assert_eq!(
            shopping::add_scaled(&[], &r, &[0], 2).unwrap()[0].quantity_text(),
            expected
        );
    }
    let r = recipe(
        "packages",
        &[
            ("beans", "1", "(14 oz) cans"),
            ("beans", "1", "(28 oz) cans"),
            ("salt", "to taste", ""),
            ("salt", "to taste", ""),
        ],
    );
    assert_eq!(
        shopping::add_scaled(&[], &r, &[0, 1, 2, 3], 2)
            .unwrap()
            .len(),
        4
    );
}
#[test]
fn shopping_table_checked_lines_are_untouched_and_unchecked_lines_combine() {
    let r = recipe("dish", &[("cream", "1/3", "cup")]);
    let mut before = shopping::add_scaled(&[], &r, &[0], 2).unwrap();
    before[0].checked = true;
    let after = shopping::add_scaled(&before, &r, &[0], 2).unwrap();
    assert_eq!(after.len(), 2);
    assert_eq!(after[0], before[0]);
    assert!(!after[1].checked);
    assert_eq!(after[1].quantity_text(), "1/3 cup");
    let again = shopping::add_scaled(&after, &r, &[0], 2).unwrap();
    assert_eq!(again.len(), 2);
    assert_eq!(again[0], before[0]);
    assert_eq!(again[1].quantity_text(), "2/3 cup");
}
#[test]
fn scaled_cup_table_matches_recipe_and_shopping_without_changing_saved_amounts() {
    for (input, scale, expected) in [
        ("2/3", 1, "1/3 cup"),
        ("1/3", 3, "1/2 cup"),
        ("1/3", 4, "2/3 cup"),
        ("2/3–1", 1, "1/3–1/2 cup"),
    ] {
        let r = recipe("scaled", &[("cream", input, "cup")]);
        let original = r.clone();
        assert_eq!(
            recipe::scaling::quantity(r.content.ingredients[0].amount, "cup", scale).unwrap(),
            expected
        );
        let added = shopping::add_scaled(&[], &r, &[0], scale).unwrap();
        assert_eq!(added[0].quantity_text(), expected);
        assert_eq!(r, original);
    }
}
#[test]
fn thousands_and_decimal_comma_reach_amount_and_ingredient_parsers() {
    for (input, expected) in [
        ("1,200", "1200"),
        ("1,5", "1 1/2"),
        ("12,345,678", "12345678"),
        ("1,200.5", "1200 1/2"),
        ("0,5", "1/2"),
        ("1,200–1,500", "1200–1500"),
    ] {
        assert_eq!(Amount::parse_new(input).unwrap().text(), expected);
    }
    for input in ["1,2,3", "1,20.5", ",5", "1,"] {
        assert!(Amount::parse_new(input).is_err(), "{input}");
    }
    let rows = recipe::paste::parse_ingredients("1,200 g flour\n1,5 kg sugar", "").unwrap();
    assert_eq!(rows[0].ingredient.amount.text(), "1200");
    assert_eq!(rows[1].ingredient.amount.text(), "1 1/2");
}
#[test]
fn removal_rebuilds_exact_shares_protects_every_other_kind_and_undo_is_targeted() {
    let a = recipe(
        "a",
        &[
            ("cream", "1/3", "cup"),
            ("flour", "800", "g"),
            ("eggs", "2", ""),
            ("salt", "to taste", ""),
        ],
    );
    let b = recipe("b", &[("cream", "1/3", "cup"), ("flour", "400", "g")]);
    let mut before = shopping::add_scaled(&[], &a, &[0, 1, 2, 3], 2).unwrap();
    before = shopping::add_scaled(&before, &b, &[0, 1], 2).unwrap();
    before[2].checked = true;
    before.push(Item::manual("typed flour".into()).unwrap());
    let mut legacy = before[0].clone();
    legacy.id = "legacy".into();
    legacy.contributions = None;
    before.push(legacy);
    let mut edited = before[1].clone();
    edited.id = "edited".into();
    edited.name = "my edited flour".into();
    edited.edited = true;
    edited.measures.clear();
    edited.contributors.clear();
    edited.contributor_scales.clear();
    before.push(edited);
    let live: HashSet<_> = [a.id.clone(), b.id.clone()].into();
    let counts = shopping::recipes_on_list(
        &before,
        &[(a.id.clone(), "A".into()), (b.id.clone(), "B".into())],
    );
    assert_eq!(counts[0].item_count, 3);
    assert_eq!(counts[1].item_count, 2);
    let (preview, after) = shopping::remove_recipe(&before, &a.id, &live).unwrap();
    assert_eq!(preview[0].action, "reduce");
    assert_eq!(preview[0].before, "2/3 cup");
    assert_eq!(preview[0].after.as_deref(), Some("1/3 cup"));
    assert_eq!(preview[1].before, "1.2 kg");
    assert_eq!(preview[1].after.as_deref(), Some("400 g"));
    assert_eq!(preview[2].reason, "Already checked off");
    assert_eq!(preview[3].action, "remove");
    assert_eq!(preview[4].reason, "Added before this update");
    assert_eq!(preview[5].reason, "Changed by hand");
    assert_eq!(preview.len(), 6);
    assert!(!preview.iter().any(|line| line.name == "typed flour"));
    let remaining_recipes = shopping::recipes_on_list(
        &after,
        &[(a.id.clone(), "A".into()), (b.id.clone(), "B".into())],
    );
    assert_eq!(remaining_recipes.len(), 1);
    assert_eq!(remaining_recipes[0].recipe_id, b.id);
    assert_eq!(remaining_recipes[0].item_count, 2);
    assert_eq!(after[0].quantity_text(), "1/3 cup");
    assert_eq!(after[1].quantity_text(), "400 g");
    let undo = shopping::Undo::between(&before, &after);
    let unrelated = Item::manual("napkins".into()).unwrap();
    let mut current = after.clone();
    current.push(unrelated.clone());
    let mut restored = before.clone();
    restored.push(unrelated);
    assert_eq!(undo.apply(&current).unwrap(), restored);
    current[0].checked = true;
    assert_eq!(undo.apply(&current), Err(Error::StaleWrite));
    let live = [a.id.clone()].into();
    let (preview, after_deleted) = shopping::remove_recipe(&before, &a.id, &live).unwrap();
    assert_eq!(preview[0].reason, "A contributing recipe was deleted");
    assert_eq!(after_deleted[0], before[0]);
    let counts = shopping::recipes_on_list(&before, &[(a.id.clone(), "A".into())]);
    assert_eq!(
        counts[0].item_count, 1,
        "Only salt is removable after B is deleted"
    );
    let (preview_b, _) =
        shopping::remove_recipe(&after, &b.id, &[a.id.clone(), b.id.clone()].into()).unwrap();
    assert!(!preview_b.iter().any(|line| line.name == "eggs"));
    let only_protected: Vec<_> = before
        .iter()
        .filter(|item| {
            ["eggs", "typed flour", "my edited flour"].contains(&item.name.as_str())
                || item.id == "legacy"
        })
        .cloned()
        .collect();
    assert!(
        shopping::recipes_on_list(
            &only_protected,
            &[(a.id.clone(), "A".into()), (b.id.clone(), "B".into())]
        )
        .is_empty()
    );
}

struct Root(PathBuf);
impl Root {
    fn new() -> Self {
        Self(std::env::temp_dir().join(format!("cookdex-shopping-{}", uuid::Uuid::new_v4())))
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
#[test]
fn native_removal_preview_stale_write_edit_and_restart() {
    let root = Root::new();
    let s = Service::open(&root).unwrap();
    let a = recipe("A", &[("cream", "1/3", "cup"), ("flour", "800", "g")]);
    let snap = s.save(0, None, a.content, &Operation::default()).unwrap();
    let id = snap.summaries[0].id.clone();
    let added = s
        .add_shopping_scaled(snap.generation, &id, &[0, 1], 2, &Operation::default())
        .unwrap()
        .snapshot;
    let preview = s.preview_shopping_removal(added.generation, &id).unwrap();
    let edit = s
        .edit_shopping(
            added.generation,
            ShoppingEdit::Edit {
                id: added.shopping[1].id.clone(),
                text: "hand-changed flour".into(),
            },
            &Operation::default(),
        )
        .unwrap()
        .snapshot;
    assert!(matches!(
        s.remove_shopping_recipe(preview.generation, &id, &Operation::default()),
        Err(Error::StaleWrite)
    ));
    drop(s);
    let s = Service::open(&root).unwrap();
    assert_eq!(
        s.shopping_recipes(edit.generation).unwrap()[0].item_count,
        1
    );
    let preview = s.preview_shopping_removal(edit.generation, &id).unwrap();
    assert_eq!(preview.lines[1].reason, "Changed by hand");
    let removed = s
        .remove_shopping_recipe(preview.generation, &id, &Operation::default())
        .unwrap();
    assert_eq!(removed.snapshot.shopping.len(), 1);
    assert_eq!(removed.snapshot.shopping[0], edit.shopping[1]);
    assert_eq!(
        s.undo_shopping(
            removed.snapshot.generation,
            &removed.undo,
            &Operation::default()
        )
        .unwrap()
        .shopping,
        edit.shopping
    );
}
