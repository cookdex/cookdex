use cookdex_core::{
    backup,
    recipe::{Amount, Ingredient, Recipe, scaling},
    shopping,
};

fn recipe(rows: &[(&str, &str)]) -> Recipe {
    let mut recipe = backup::read(include_bytes!("fixtures/compatibility/schema2.zip"))
        .unwrap()
        .remove(0);
    recipe.content.ingredients = rows
        .iter()
        .map(|(amount, unit)| Ingredient {
            amount: Amount::parse_exact(amount).unwrap(),
            unit: (*unit).into(),
            name: "flour".into(),
            prep_note: String::new(),
            optional: false,
            section: String::new(),
        })
        .collect();
    recipe
}

#[test]
fn scaling_keeps_original_weight_units_for_counts_and_ranges() {
    for (amount, unit, scale, expected) in [
        ("16", "oz", 4, "32 oz"),
        ("1", "lb", 1, "1/2 lb"),
        ("750", "g", 4, "1500 g"),
        ("1", "kg", 1, "1/2 kg"),
        ("8–16", "oz", 4, "16–32 oz"),
        ("8", "tbsp", 4, "1 cup"),
        ("500", "ml", 4, "1 l"),
    ] {
        assert_eq!(
            scaling::quantity(Amount::parse_exact(amount).unwrap(), unit, scale).unwrap(),
            expected
        );
    }
}

#[test]
fn same_weight_units_stay_and_mixed_units_choose_largest_in_either_order() {
    for (rows, expected) in [
        ([("16", "oz"), ("16", "oz")], "32 oz"),
        ([("750", "g"), ("750", "g")], "1500 g"),
        ([("8", "oz"), ("1", "lb")], "1 1/2 lb"),
        ([("500", "g"), ("1", "kg")], "1 1/2 kg"),
        ([("1", "g"), ("1/2", "kg")], "501/1000 kg"),
        ([("8–16", "oz"), ("1–2", "lb")], "1 1/2–3 lb"),
        ([("8", "tbsp"), ("1", "cup")], "1 1/2 cups"),
    ] {
        for reverse in [false, true] {
            let rows = if reverse { [rows[1], rows[0]] } else { rows };
            let a = recipe(&rows[..1]);
            let mut b = recipe(&rows[1..]);
            b.id.0 = "second-recipe".into();
            let before = a.clone();
            let first = shopping::add_scaled(&[], &a, &[0], 2).unwrap();
            let sum = shopping::add_scaled(&first, &b, &[0], 2).unwrap();
            assert_eq!(sum.len(), 1);
            assert_eq!(sum[0].quantity_text(), expected);
            assert_eq!(sum[0].contributors.len(), 2);
            assert_eq!(
                shopping::Undo::between(&first, &sum).apply(&sum).unwrap(),
                first
            );
            assert_eq!(a, before);
        }
    }
    let r = recipe(&[("16", "oz")]);
    let items = shopping::add_scaled(&[], &r, &[0], 4).unwrap();
    assert_eq!(items[0].quantity_text(), "32 oz");
}

#[test]
fn legacy_separate_weight_measures_consolidate_into_largest_present_unit() {
    for reverse in [false, true] {
        let old = recipe(&[("1", "g")]);
        let mut items = shopping::add(&[], &old, &[0]).unwrap();
        items[0].measures.push(shopping::Measure {
            amount: Amount::parse_exact("1").unwrap(),
            unit: "lb".into(),
        });
        if reverse {
            items[0].measures.reverse();
        }
        items[0].measures.push(shopping::Measure {
            amount: Amount::parse_exact("2").unwrap(),
            unit: "cup".into(),
        });
        // Previous releases persisted separate mass measures for awkward conversions.
        let items: Vec<shopping::Item> =
            serde_json::from_slice(&serde_json::to_vec(&items).unwrap()).unwrap();
        let mut incoming = recipe(&[("1", "oz")]);
        incoming.id.0 = "incoming".into();
        let sum = shopping::add(&items, &incoming, &[0]).unwrap();
        assert_eq!(sum[0].measures.len(), 2);
        assert_eq!(sum[0].measures[0].unit, "lb");
        assert_eq!(
            sum[0].measures[0].amount,
            Amount::parse_exact("772707029/725747792").unwrap()
        );
        assert_eq!(sum[0].measures[1], items[0].measures[2]);
        assert_eq!(sum[0].contributors.len(), 2);
        assert_eq!(
            shopping::Undo::between(&items, &sum).apply(&sum).unwrap(),
            items
        );
    }
}
