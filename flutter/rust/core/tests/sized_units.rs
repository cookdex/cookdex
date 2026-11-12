use cookdex_core::{
    backup,
    recipe::{Amount, Ingredient, Recipe, scaling, text, units},
    shopping,
};

const NOW: &str = "2026-01-02T03:04:05Z";

fn recipe(rows: &[(&str, &str)]) -> Recipe {
    let mut recipe = backup::read(include_bytes!("fixtures/compatibility/schema2.zip"))
        .unwrap()
        .remove(0);
    recipe.content.ingredients = rows
        .iter()
        .map(|(amount, unit)| Ingredient {
            amount: Amount::parse_exact(amount).unwrap(),
            unit: (*unit).into(),
            name: "diced tomatoes".into(),
            prep_note: String::new(),
            optional: false,
            section: String::new(),
        })
        .collect();
    recipe
}

#[test]
fn container_counts_pluralize_without_touching_size() {
    for (singular, plural) in [
        ("can", "cans"),
        ("jar", "jars"),
        ("bottle", "bottles"),
        ("box", "boxes"),
        ("bag", "bags"),
        ("package", "packages"),
    ] {
        for suffix in [singular, plural] {
            let unit = format!("(14 OZ) {suffix}");
            for (amount, scale, expected) in [
                ("2", 1, format!("1 (14 OZ) {singular}")),
                ("2", 4, format!("4 (14 OZ) {plural}")),
                ("1/2", 2, format!("1/2 (14 OZ) {singular}")),
                ("1–2", 2, format!("1–2 (14 OZ) {plural}")),
            ] {
                assert_eq!(
                    scaling::quantity(Amount::parse_exact(amount).unwrap(), &unit, scale).unwrap(),
                    expected
                );
            }
            assert_eq!(units::normalize(&unit), unit);
        }
        assert_eq!(units::normalize(plural), singular);
    }
    assert_eq!(
        units::display("(family size) tubs", Amount::parse_exact("1").unwrap()),
        "(family size) tubs"
    );
}

#[test]
fn shopping_merges_matching_sizes_and_keeps_other_sizes_on_separate_rows() {
    let a = recipe(&[("2", "(4 oz) cans"), ("1", "(10 oz) can"), ("1", "can")]);
    let original = a.clone();
    let items = shopping::add_scaled(&[], &a, &[0, 1, 2], 2).unwrap();
    assert_eq!(items.len(), 3);
    let mut b = recipe(&[("1", "(4 oz) can"), ("1", "(10 oz) cans")]);
    b.id.0 = "second-recipe".into();
    let merged = shopping::add_scaled(&items, &b, &[0, 1], 4).unwrap();
    assert_eq!(merged.len(), 3);
    assert_eq!(
        merged.iter().map(|i| i.quantity_text()).collect::<Vec<_>>(),
        ["4 (4 oz) cans", "3 (10 oz) cans", "1 can"]
    );
    assert_eq!(merged[0].contributors.len(), 2);
    assert_eq!(merged[2].contributors.len(), 1);
    let reopened: Vec<shopping::Item> =
        serde_json::from_slice(&serde_json::to_vec(&merged).unwrap()).unwrap();
    assert_eq!(reopened, merged);
    assert_eq!(
        shopping::Undo::between(&items, &merged)
            .apply(&merged)
            .unwrap(),
        items
    );
    assert_eq!(a, original);
    let fractional = recipe(&[("1/3", "(4 oz) can"), ("1/3", "(4 oz) cans")]);
    let merged = shopping::add(&[], &fractional, &[0, 1]).unwrap();
    assert_eq!(merged[0].measures.len(), 1);
    assert_eq!(merged[0].quantity_text(), "2/3 (4 oz) can");
}

#[test]
fn sized_units_are_exact_through_editor_text_sharing_and_zip() {
    let recipe = recipe(&[
        ("2", "(14 oz) cans"),
        ("1", "(16 OZ) Jar"),
        ("1–2", "(250 ml)  bottles"),
    ]);
    assert_eq!(
        recipe
            .content
            .parse_editor(&[None, None, None])
            .unwrap()
            .ingredients,
        recipe.content.ingredients
    );
    let single = text::export_recipe(&recipe).unwrap();
    assert_eq!(
        text::import_text(&single, NOW).unwrap().candidates[0]
            .recipe
            .content,
        recipe.content
    );
    let mut second = recipe.clone();
    second.id.0 = "second".into();
    second.content.title = "Another pantry supper".into();
    let shared = text::export_cookbook(&[recipe.clone(), second.clone()]).unwrap();
    let imported = text::import_text(&shared, NOW).unwrap();
    assert_eq!(imported.candidates[0].recipe.content, recipe.content);
    assert_eq!(imported.candidates[1].recipe.content, second.content);
    assert_eq!(
        backup::read(&backup::write(&[recipe.clone(), second.clone()]).unwrap()).unwrap(),
        [recipe, second]
    );
}

#[test]
fn count_units_pluralize_for_display_without_mutating_recipe() {
    for (single, plural) in [
        ("clove", "cloves"),
        ("slice", "slices"),
        ("sprig", "sprigs"),
        ("stalk", "stalks"),
        ("head", "heads"),
        ("bunch", "bunches"),
    ] {
        let original = recipe(&[("3", single)]);
        let saved = original.clone();
        assert_eq!(
            units::display(single, Amount::parse_exact("3").unwrap()),
            plural
        );
        assert_eq!(
            units::display(single, Amount::parse_exact("1–2").unwrap()),
            plural
        );
        assert_eq!(
            units::display(single, Amount::parse_exact("1/2").unwrap()),
            single
        );
        assert_eq!(
            units::display(plural, Amount::parse_exact("3").unwrap()),
            plural
        );
        let rows = shopping::add(&[], &original, &[0]).unwrap();
        assert_eq!(rows[0].quantity_text(), format!("3 {plural}"));
        assert_eq!(original, saved);
    }
}

#[test]
fn implicit_sized_container_plain_text_is_one_without_guessing_plural_counts() {
    use cookdex_core::recipe::paste;
    let rows =
        paste::parse_ingredients("16 oz jar of salsa verde\n250 ml bottle broth", "").unwrap();
    assert_eq!(rows[0].ingredient.amount.text(), "1");
    assert_eq!(rows[0].ingredient.unit, "(16 oz) jar");
    assert_eq!(rows[0].ingredient.name, "salsa verde");
    assert_eq!(rows[1].ingredient.unit, "(250 ml) bottle");
    assert!(rows.iter().all(|row| row.issue.is_none()));
    for input in [
        "16 oz jars of salsa",
        "family size jar salsa",
        "0 oz jar salsa",
        "16–20 oz jar salsa",
        "16 oz jar",
        "2 (16 oz) jars salsa",
    ] {
        assert!(units::implicit_package(input).is_none(), "{input}");
    }
}
