use cookdex_core::recipe::{
    self, Amount, AmountInput, Rational, Recipe, amount::MAX_INTEGER, model, paste, text, web,
};
use serde_json::{Value, json};
const NOW: &str = "2026-01-02T03:04:05.000Z";
fn corpus() -> Value {
    serde_json::from_str(include_str!("../../../../tests/fixtures/corpus.json")).unwrap()
}
fn sample() -> Recipe {
    Recipe::from_json(&serde_json::to_vec(&corpus()["recipes"][0]).unwrap()).unwrap()
}
fn written(token: &str) -> Value {
    json!({"title":"Written recipe","description":"","servings":"","prepTime":"","cookTime":"","totalTime":"","source":"","tags":[],"notes":"","ingredients":[{"amount":token,"name":"oil","unit":"cup","prepNote":"","section":"Sauce","optional":false}],"steps":["Mix."]})
}
fn page(value: Value) -> String {
    format!("<script type=\"application/ld+json\">{value}</script>")
}
fn embedded(token: &str) -> Value {
    json!({"@type":"Recipe","name":"Soup","recipeIngredient":[format!("{token} cup oil")],"recipeInstructions":["Mix."]})
}

#[test]
fn frozen_c0_canonical_fields_and_amounts_round_trip_without_snapping() {
    for value in corpus()["recipes"].as_array().unwrap() {
        let r = Recipe::from_json(&serde_json::to_vec(value).unwrap()).unwrap();
        let mut migrated = value.clone();
        migrated["schemaVersion"] = json!(2);
        assert_eq!(serde_json::to_value(&r).unwrap(), migrated);
        assert_eq!(Recipe::from_json(&r.to_json().unwrap()).unwrap(), r);
        let cream = r.content.ingredients[1].amount;
        assert_eq!(cream.text(), "33/100");
        assert_eq!(
            Amount::from_input(AmountInput::Unchanged(cream)).unwrap(),
            cream
        );
    }
}
#[test]
fn c0_exact_and_new_input_oracles() {
    for row in corpus()["quantityCases"].as_array().unwrap() {
        let input = row["input"].as_str().unwrap();
        assert_eq!(
            serde_json::to_value(Amount::parse_exact(input).unwrap()).unwrap(),
            row["tauriExact"]
        );
        assert_eq!(
            serde_json::to_value(Amount::parse_new(input).unwrap()).unwrap(),
            row["flutterNewInput"]
        );
    }
}
#[test]
fn written_quantity_policy_and_exact_interchange_are_distinct() {
    for (token, expected) in [
        ("0.33", "1/3"),
        ("0.3", "3/10"),
        ("33/100", "33/100"),
        ("1.499", "1 1/2"),
        ("1 33/100", "1 33/100"),
        ("1½", "1 1/2"),
        ("1 ½", "1 1/2"),
        ("2 ¼", "2 1/4"),
        ("0.125", "1/8"),
        ("0.25", "1/4"),
        ("0.5", "1/2"),
        ("0.667", "2/3"),
        ("0.75", "3/4"),
        ("0.99", "1"),
    ] {
        assert_eq!(
            Amount::from_input(AmountInput::Written(token))
                .unwrap()
                .text(),
            expected
        );
        let line = format!("{token} cup oil");
        assert_eq!(
            paste::parse_ingredients(&line, "Sauce").unwrap()[0]
                .ingredient
                .amount
                .text(),
            expected
        );
        let ordinary =
            paste::parse_recipe_input(&format!("Soup\nIngredients:\n{line}\nSteps:\nMix."), NOW)
                .unwrap();
        assert_eq!(
            ordinary.candidates[0].recipe.content.ingredients[0]
                .amount
                .text(),
            expected
        );
        let strict =
            text::export_recipe(&sample())
                .unwrap()
                .replacen("- 1/3 |", &format!("- {token} |"), 1);
        assert_eq!(
            text::import_text(&strict, NOW).unwrap().candidates[0]
                .recipe
                .content
                .ingredients[0]
                .amount
                .text(),
            Amount::parse_exact(token).unwrap().text()
        );
        let ld = web::inspect_page(&page(embedded(token)), "https://example.test", NOW).unwrap();
        assert_eq!(
            ld.imports.candidates[0].recipe.content.ingredients[0]
                .amount
                .text(),
            expected
        );
        assert_eq!(
            model::parse_ai_written(&written(token).to_string(), NOW)
                .unwrap()
                .content
                .ingredients[0]
                .amount
                .text(),
            expected
        );
    }
}
#[test]
fn exact_arithmetic_formatting_conversion_and_bounds() {
    let third = Rational::new(1, 3).unwrap();
    assert_eq!(third.checked_add(third).unwrap().text(), "2/3");
    assert_eq!(
        Rational::new(1, 1)
            .unwrap()
            .convert(
                Rational::new(1000, 1).unwrap(),
                Rational::new(1, 1).unwrap()
            )
            .unwrap()
            .text(),
        "1000"
    );
    assert_eq!(
        Rational::new(1, 1)
            .unwrap()
            .convert(
                Rational::new(45359237, 100000).unwrap(),
                Rational::new(28349523125, 1000000000).unwrap()
            )
            .unwrap()
            .text(),
        "16"
    );
    let max = Rational::new(MAX_INTEGER as u128, 1).unwrap();
    assert_eq!(max.convert(max, max).unwrap(), max);
    assert!(max.checked_add(Rational::new(1, 1).unwrap()).is_err());
    assert_eq!(
        Amount::parse_new("9007199254740991").unwrap().text(),
        MAX_INTEGER.to_string()
    );
    for invalid in [
        "0",
        "0.0",
        "-1",
        "1/0",
        "abc",
        ".5",
        "1.",
        "1e3",
        "NaN",
        "2-1",
        "9007199254740992",
        "1/9007199254740992",
        "0.00000000000000001",
        "1/2/3",
    ] {
        assert!(Amount::parse_new(invalid).is_err(), "{invalid}");
    }
    for exact in ["33/100", "1 33/100", "⅜", "⅝", "⅞"] {
        assert_eq!(
            Amount::parse_new(exact).unwrap(),
            Amount::parse_exact(exact).unwrap()
        );
    }
    assert_eq!(Amount::parse_new("").unwrap(), Amount::Unspecified);
    assert_eq!(Amount::parse_new("TO TASTE").unwrap(), Amount::ToTaste);
}
#[test]
fn canonical_malformed_variants_fail_closed() {
    for bad in [
        json!({"kind":"number","numerator":0,"denominator":1}),
        json!({"kind":"number","numerator":1,"denominator":0}),
        json!({"kind":"number","numerator":1.5,"denominator":1}),
        json!({"kind":"number","numerator":MAX_INTEGER+1,"denominator":MAX_INTEGER+1}),
        json!({"kind":"unspecified","numerator":1}),
        json!({"kind":"range"}),
        json!({"kind":"number","numerator":1,"denominator":2,"extra":true}),
    ] {
        assert!(
            serde_json::from_value::<Amount>(bad.clone()).is_err(),
            "{bad}"
        );
    }
    let good = serde_json::to_value(sample()).unwrap();
    for (key, value) in [
        ("schemaVersion", json!(3)),
        ("id", json!("")),
        ("title", json!(" ")),
        ("revision", json!(0)),
        ("revision", json!(MAX_INTEGER + 1)),
        ("createdAt", json!("not a date")),
        ("source", json!("javascript:alert(1)")),
        ("favorite", json!("yes")),
        ("prepTime", json!("a".repeat(81))),
        ("tags", json!([false])),
        ("steps", json!([{}])),
    ] {
        let mut bad = good.clone();
        bad[key] = value;
        assert!(
            Recipe::from_json(&serde_json::to_vec(&bad).unwrap()).is_err(),
            "{key}"
        );
    }
    for source in ["http://example.test/a", "https://example.test/é?q=a#b"] {
        assert!(model::safe_source(source));
    }
    for source in [
        "file:///secret",
        "data:text/html,bad",
        "https://",
        "not a URL",
    ] {
        assert!(!model::safe_source(source));
    }
}
#[test]
fn ingredient_groups_keep_first_appearance_original_names_and_indices() {
    let mut r = sample();
    r.content.ingredients[2].section = "  BASE  ".into();
    let groups = model::ingredient_groups(&r.content.ingredients);
    assert_eq!(
        groups.iter().map(|g| g.indices.clone()).collect::<Vec<_>>(),
        vec![vec![0, 2], vec![1, 3, 4]]
    );
    assert_eq!(groups[0].name, "Base");
    assert_eq!(model::normalize_name(" Olive  oil "), "olive oil");
    assert_eq!(r.content.ingredients[0].text(), "1/3 cup oil, extra virgin");
}
#[test]
fn text_new_output_preserves_content_and_omits_all_metadata() {
    let mut r = sample();
    r.content.tags = vec!["".into(), "tag | one".into(), "tag\nline".into()];
    r.content
        .notes
        .push_str("\n--- End recipe ---\nTrailing space ");
    let text = text::export_recipe(&r).unwrap();
    for prefix in [
        "Metadata:",
        "Created:",
        "Updated:",
        "Revision:",
        "Favorite:",
        &r.id.0,
    ] {
        assert!(!text.contains(prefix));
    }
    let imported = text::import_text(&text, NOW)
        .unwrap()
        .select(0)
        .unwrap()
        .0
        .recipe;
    assert_eq!(imported.content, r.content);
    assert_ne!(imported.id, r.id);
    assert_eq!(imported.revision, 1);
    assert!(!imported.favorite);
    assert_eq!(imported.created_at, NOW);
}
#[test]
fn legacy_metadata_text_and_multiple_candidates_are_supported() {
    let c = corpus();
    let legacy = c["legacyText"].as_str().unwrap();
    let parsed = text::import_text(legacy, NOW).unwrap();
    for (i, candidate) in parsed.candidates.iter().enumerate() {
        let original = Recipe::from_json(&serde_json::to_vec(&c["recipes"][i]).unwrap()).unwrap();
        assert_eq!(candidate.recipe.content, original.content);
        assert_eq!(candidate.recipe.favorite, original.favorite);
        assert_eq!(candidate.recipe.revision, original.revision);
        assert_eq!(candidate.recipe.created_at, original.created_at);
        assert_eq!(candidate.recipe.updated_at, original.updated_at);
    }
    let exported = text::export_cookbook(&[sample(), sample()])
        .unwrap()
        .replace('\n', "\r\n");
    let result = paste::parse_recipe_input(&format!("\u{feff}{exported}"), NOW).unwrap();
    assert_eq!(result.candidates.len(), 2);
    assert!(!result.ordinary);
    let expected = sample().content;
    assert_eq!(result.select(1).unwrap().0.recipe.content, expected);
    assert!(result.select(2).is_err());
}
#[test]
fn strict_text_rejects_malformed_grammar_without_ordinary_fallback() {
    let good = text::export_recipe(&sample()).unwrap();
    for repairable in [
        good.replace(" | yes", " | maybe"),
        good.replace("Tags: [", "Tags: {"),
        good.replace(" | oil |", " |  |"),
        good.replace("- 1/3 |", "- 1/0 |"),
    ] {
        assert!(paste::parse_recipe_input(&repairable, NOW).is_err());
    }
    for bad in [
        "Recipe Book Text v1\nTitle: Broken".into(),
        good.replace("1. Mix", "2. Mix"),
        good.replace("\\|", "\\q"),
        good.replace("--- End recipe ---", ""),
        good.replace("Title: ", "Title "),
    ] {
        assert!(paste::parse_recipe_input(&bad, NOW).is_err());
    }
    assert!(
        text::import_text(
            &std::iter::repeat_n(good.as_str(), 51)
                .collect::<Vec<_>>()
                .join("\n\n"),
            NOW
        )
        .unwrap()
        .candidates
        .len()
            == 51
    );
}
#[test]
fn ingredient_paste_retains_components_quantities_preparation_and_review_lines() {
    let rows=paste::parse_ingredients("Sauce:\n• 1 1/2 tbsp olive oil\n3 cloves garlic, minced\nDough:\n250g flour\n½ cup water\nSalt to taste","").unwrap();
    assert_eq!(
        rows.iter()
            .map(|r| r.ingredient.amount.text())
            .collect::<Vec<_>>(),
        ["1 1/2", "3", "250", "1/2", "to taste"]
    );
    assert_eq!(rows[1].ingredient.prep_note, "minced");
    assert_eq!(rows[2].ingredient.section, "Dough");
    assert!(rows.iter().all(|r| r.issue.is_none()));
    for line in [
        "2-1 onions",
        "2 (400 g) cans tomatoes",
        "Fresh parsley",
        "1/0 cup flour",
        "0 eggs",
        "0.00 cup milk",
        "1e3 cup flour",
        "1E+3 g flour",
        "1e-3 cup oil",
    ] {
        let r = paste::parse_ingredients(line, "Batter").unwrap().remove(0);
        assert!(r.issue.is_some(), "{line}");
        assert_eq!(r.original, line);
        assert_eq!(r.ingredient.name, line);
        assert_eq!(r.ingredient.amount, Amount::Unspecified);
        assert_eq!(r.ingredient.section, "Batter");
    }
    assert!(
        paste::parse_ingredients("Sauce:\n\n", "")
            .unwrap()
            .is_empty()
    );
    assert_eq!(
        paste::parse_ingredients("2 eggs", "Batter").unwrap()[0]
            .ingredient
            .section,
        "Batter"
    );
}
#[test]
fn ordinary_recipe_preserves_unknown_text_and_invalid_attribution() {
    let result=paste::parse_recipe_input("Soup\nServes: 4\nPrep time: 10 minutes\nA family recipe\nSource: Grandma\nIngredients:\nSauce:\n1/3 cup oil\n2 tomatoes, diced\nMethod:\n1. Mix.\n2. Simmer.\nNotes:\nTaste before serving.",NOW).unwrap();
    let r = &result.candidates[0].recipe.content;
    assert_eq!(r.prep_time, "10 min");
    assert_eq!(r.ingredients[0].section, "Sauce");
    assert_eq!(r.ingredients[1].prep_note, "diced");
    assert_eq!(r.steps, ["Mix.", "Simmer."]);
    assert!(r.notes.contains("A family recipe"));
    assert!(r.notes.contains("Source: Grandma"));
    assert!(r.source.is_empty());
    assert!(result.ordinary);
    let r = paste::parse_recipe_input(
        "Beans\nIngredients:\n1 (15 oz) can beans\nSalt to taste",
        NOW,
    )
    .unwrap();
    assert_eq!(
        r.candidates[0].recipe.content.ingredients[0].name,
        "1 (15 oz) can beans"
    );
    assert!(r.warnings.iter().any(|w| w.contains("No steps")));
    assert!(paste::parse_recipe_input(" ", NOW).is_err());
}
#[test]
fn saved_json_ld_fixtures_map_metadata_entities_sections_and_instructions() {
    let p = web::inspect_page(
        include_str!("../../../../tests/fixtures/smart-import/recipe.html"),
        "https://example.test/sauce",
        NOW,
    )
    .unwrap();
    let r = &p.imports.candidates[0].recipe.content;
    assert_eq!(r.title, "Lemon & herb sauce");
    assert_eq!(r.description, "A sauce & dip.");
    assert_eq!(r.ingredients[0].amount.text(), "1/3");
    assert_eq!(r.ingredients[1].prep_note, "minced");
    assert_eq!(r.ingredients[2].amount, Amount::ToTaste);
    assert_eq!(r.ingredients[3].name, "1 (14 ounce) can tomatoes");
    assert!(r.notes.contains("Keeps for two days"));
    assert!(r.notes.contains("1 (14 ounce) can tomatoes"));
    assert_eq!(r.steps, ["Mix the oil & garlic.", "Season and serve."]);
    assert!(p.text.contains("180°C"));
    assert!(!p.text.contains("Advertisement"));
    assert!(!p.text.contains("fixtureExecuted"));
    let p = web::inspect_page(
        include_str!("../../../../tests/fixtures/smart-import/multiple-graph.html"),
        "https://example.test/recipes",
        NOW,
    )
    .unwrap();
    assert_eq!(p.imports.candidates.len(), 2);
    let r = &p.imports.candidates[0].recipe.content;
    assert_eq!(r.servings, "1 loaf, 8 slices");
    assert_eq!(r.ingredients[0].amount.text(), "1 1/2");
    assert_eq!(r.ingredients[0].section, "Dough");
    assert_eq!(r.ingredients.last().unwrap().section, "Topping");
    assert_eq!(
        r.steps,
        ["Make dough", "Mix.", "Knead.", "Bake", "Bake until golden."]
    );
    assert_eq!(
        p.imports.candidates[1].recipe.content.steps,
        ["Steep and strain."]
    );
    assert!(
        p.imports
            .warnings
            .iter()
            .any(|w| w.contains("could not be read"))
    );
}
#[test]
fn html_readable_text_and_empty_metadata_only_pages() {
    let html = include_str!("../../../../tests/fixtures/smart-import/no-jsonld.html");
    let s = web::readable_text(html).unwrap();
    assert!(s.contains("Soup"));
    assert!(s.contains("½ tsp salt"));
    assert!(s.contains("Heat & stir"));
    assert!(!s.contains("Login"));
    assert!(!s.contains("should never run"));
    assert_eq!(s, web::readable_text(html).unwrap());
    assert_eq!(
        web::readable_text("<p>&#x1F34B; &lt;script&gt; x</p>").unwrap(),
        "🍋 <script> x"
    );
    assert_eq!(
        web::readable_text(include_str!(
            "../../../../tests/fixtures/smart-import/empty.html"
        ))
        .unwrap(),
        ""
    );
    let p = web::inspect_page(
        include_str!("../../../../tests/fixtures/smart-import/metadata-only-visible-recipe.html"),
        "https://example.test/sandwich",
        NOW,
    )
    .unwrap();
    assert_eq!(p.imports.candidates.len(), 1);
    assert!(
        p.imports
            .warnings
            .iter()
            .any(|w| w.contains("missing ingredients and directions"))
    );
    assert!(p.text.contains("Butter the bread"));
}
#[test]
fn json_ld_depth_nodes_candidates_and_malformed_neighbors_are_bounded() {
    let mut deep = embedded("1");
    for _ in 0..40 {
        deep = json!({"child":deep});
    }
    let p = web::inspect_page(
        &page(json!([deep,{"@type":"Recipe"},embedded("1")])),
        "",
        NOW,
    )
    .unwrap();
    assert_eq!(p.imports.candidates.len(), 1);
    assert!(p.imports.warnings.iter().any(|w| w.contains("too complex")));
    assert!(p.imports.warnings.iter().any(|w| w.contains("incomplete")));
    let p = web::inspect_page(
        &page(json!((0..60).map(|_| embedded("1")).collect::<Vec<_>>())),
        "",
        NOW,
    )
    .unwrap();
    assert_eq!(p.imports.candidates.len(), 50);
    assert!(p.imports.warnings.iter().any(|w| w.contains("first 50")));
    let p = web::inspect_page(
        &page(json!(
            (0..21000).map(|_| json!({"x":[]})).collect::<Vec<_>>()
        )),
        "",
        NOW,
    )
    .unwrap();
    assert!(p.imports.warnings.iter().any(|w| w.contains("too complex")));
    let mut nested = json!("Mix.");
    for _ in 0..40 {
        nested = json!({"item":nested});
    }
    let mut bad = embedded("1");
    bad["recipeInstructions"] = nested;
    assert!(web::map_json_ld(&bad, "", NOW).is_err());
}
#[test]
fn json_ld_durations_source_fallback_and_partial_data() {
    let mut v = embedded("1");
    v["prepTime"] = json!("PT15M");
    v["cookTime"] = json!("PT1H20M");
    v["totalTime"] = json!("PT1H35M");
    v["url"] = json!("javascript:bad");
    let r = web::map_json_ld(&v, "https://example.test/soup", NOW)
        .unwrap()
        .recipe
        .content;
    assert_eq!(r.prep_time, "15 min");
    assert_eq!(r.cook_time, "1 hr 20 min");
    assert_eq!(r.total_time, "1 hr 35 min");
    assert_eq!(r.source, "https://example.test/soup");
    for missing in ["recipeIngredient", "recipeInstructions"] {
        let mut v = embedded("1");
        v.as_object_mut().unwrap().remove(missing);
        assert!(!web::map_json_ld(&v, "", NOW).unwrap().warnings.is_empty());
    }
}
#[test]
fn ai_written_shape_rejects_rational_objects_unknown_fields_and_metadata() {
    let good = written("0.33");
    for bad in [
        json!({}),
        json!([]),
        {
            let mut v = good.clone();
            v["ingredients"][0]["amount"] =
                json!({"kind":"number","numerator":33,"denominator":100});
            v
        },
        {
            let mut v = good.clone();
            v["id"] = json!("injected");
            v
        },
        {
            let mut v = good.clone();
            v["ingredients"][0]["unknown"] = json!(true);
            v
        },
        {
            let mut v = good.clone();
            v["ingredients"][0]["optional"] = json!("yes");
            v
        },
        {
            let mut v = good.clone();
            v["title"] = json!(" ");
            v
        },
        {
            let mut v = good.clone();
            v.as_object_mut().unwrap().remove("steps");
            v
        },
    ] {
        assert!(model::parse_ai_written(&bad.to_string(), NOW).is_err());
    }
}
#[test]
fn encoded_byte_and_collection_field_limits_fail_before_import() {
    let big = "é".repeat(recipe::MAX_INPUT_BYTES / 2 + 1);
    assert!(paste::parse_recipe_input(&big, NOW).is_err());
    assert!(paste::parse_ingredients(&big, "").is_err());
    assert!(text::import_text(&big, NOW).is_err());
    assert!(web::inspect_page(&big, "", NOW).is_err());
    assert!(model::parse_ai_written(&big, NOW).is_err());
    let mut r = sample();
    r.content.tags = vec![String::new(); 10000];
    assert!(r.validate().is_ok());
    r.content.tags.push(String::new());
    assert!(r.validate().is_err());
    let mut r = sample();
    r.content.title = "🍋".repeat(80);
    assert!(r.validate().is_ok());
    r.content.title.push('a');
    assert!(r.validate().is_err());
    let mut v = written("1");
    v["ingredients"] = json!(
        (0..10001)
            .map(|_| written("1")["ingredients"][0].clone())
            .collect::<Vec<_>>()
    );
    assert!(model::parse_ai_written(&v.to_string(), NOW).is_err());
}

#[test]
fn raw_ai_lists_and_fields_are_bounded_before_normalization() {
    for key in ["tags", "steps"] {
        let mut v = written("1");
        v[key] = json!(vec![""; 10000]);
        assert!(model::parse_ai_written(&v.to_string(), NOW).is_ok());
        v[key] = json!(vec![""; 10001]);
        assert!(model::parse_ai_written(&v.to_string(), NOW).is_err());
        v[key] = json!(vec!["duplicate"; 10001]);
        assert!(model::parse_ai_written(&v.to_string(), NOW).is_err());
    }
    let mut v = written("1");
    v["title"] = json!(format!("{}Soup", " ".repeat(160)));
    assert!(model::parse_ai_written(&v.to_string(), NOW).is_err());
    let mut v = written("1");
    v["ingredients"][0]["name"] = json!(format!("{}oil", " ".repeat(2000)));
    assert!(model::parse_ai_written(&v.to_string(), NOW).is_err());
}

#[test]
fn numbered_lines_in_explicit_ingredients_remain_reviewable_ingredients() {
    let parsed = paste::parse_recipe_input(
        "Soup\nIngredients:\n1. flour\n2. milk\nSteps:\n1. Mix.",
        NOW,
    )
    .unwrap();
    let r = &parsed.candidates[0].recipe.content;
    assert_eq!(
        r.ingredients
            .iter()
            .map(|i| i.name.as_str())
            .collect::<Vec<_>>(),
        ["1. flour", "2. milk"]
    );
    assert_eq!(r.steps, ["Mix."]);
    assert!(parsed.warnings.iter().any(|w| w.contains("1. flour")));
}

#[test]
fn json_ld_null_primary_fields_fall_back_without_losing_content() {
    let value = json!({"@type":"Recipe","name":"Soup","recipeIngredient":null,"ingredients":["1 cup water"],"recipeInstructions":[
        {"@type":"HowToSection","name":"Make soup","itemListElement":null,"steps":["Boil."]},
        {"itemListElement":null,"item":{"text":"Stir."}},
        {"itemListElement":false,"text":"Serve."}
    ]});
    let c = web::map_json_ld(&value, "", NOW).unwrap();
    assert_eq!(c.recipe.content.ingredients[0].name, "water");
    assert_eq!(
        c.recipe.content.steps,
        ["Make soup", "Boil.", "Stir.", "Serve."]
    );
}

#[test]
fn temporary_storage_sync_backup_and_previous_save_keep_canonical_amounts() {
    use cookdex_core::{storage, sync_store};
    struct Sandbox(std::path::PathBuf);
    impl Drop for Sandbox {
        fn drop(&mut self) {
            std::fs::remove_dir_all(&self.0).unwrap();
        }
    }
    let root = Sandbox(std::env::temp_dir().join(format!("cookdex-c2-{}", uuid::Uuid::new_v4())));
    std::fs::create_dir(&root.0).unwrap();
    let mut a = storage::open(&root.0.join("a.sqlite3")).unwrap();
    let mut b = storage::open(&root.0.join("b.sqlite3")).unwrap();
    let original = sample();
    let value = serde_json::to_value(&original).unwrap();
    let book = storage::Book {
        recipes: vec![value.clone()],
        ..Default::default()
    };
    storage::save(&mut a, 0, &book, NOW).unwrap();
    sync_store::merge(&mut b, sync_store::export(&a).unwrap(), NOW).unwrap();
    assert_eq!(storage::load(&mut b).unwrap().book.recipes, [value.clone()]);
    assert_eq!(storage::backup_recipes(&mut b).unwrap(), [value.clone()]);
    drop(a);
    let mut a = storage::open(&root.0.join("a.sqlite3")).unwrap();
    let loaded = storage::load(&mut a).unwrap();
    assert_eq!(
        Recipe::from_json(&serde_json::to_vec(&loaded.book.recipes[0]).unwrap()).unwrap(),
        original
    );
    storage::save(&mut a, loaded.generation, &storage::Book::default(), NOW).unwrap();
    let previous = storage::previous(&a).unwrap().unwrap();
    let recovered: storage::Book = serde_json::from_value(previous["book"].clone()).unwrap();
    storage::save(&mut a, 2, &recovered, NOW).unwrap();
    assert_eq!(storage::load(&mut a).unwrap().book.recipes, [value]);
}

#[test]
fn tag_normalization_preserves_instruction_and_other_field_case() {
    let mut value = written("33/100");
    value["tags"] = json!(["Dinner", "DINNER", " Quick "]);
    value["steps"] = json!(["  Heat the Oven to 180C.  "]);
    let parsed: recipe::WrittenRecipe = serde_json::from_value(value).unwrap();
    let content = parsed.parse().unwrap();
    assert_eq!(content.tags, vec!["dinner", "quick"]);
    assert_eq!(content.steps, vec!["Heat the Oven to 180C."]);
    assert_eq!(content.title, "Written recipe");
    assert_eq!(content.ingredients[0].section, "Sauce");
    assert_eq!(content.ingredients[0].amount.text(), "33/100");
}

#[test]
fn explicit_ordinary_recipe_blocks_are_bounded_and_keep_written_sources() {
    use cookdex_core::recipe::paste::split_recipe_text;
    let a = "Cream\nIngredients:\n0.33 cup cream\nSteps:\nMix.";
    let b = "Oil\nIngredients:\n33/100 cup oil\nDirections:\nStir.";
    for input in [
        format!("{a}\n---\n{b}"),
        format!("# {a}\n# {b}"),
        format!("Recipe: {a}\nRecipe: {b}"),
    ] {
        let blocks = split_recipe_text(&input).unwrap();
        assert_eq!(blocks.len(), 2);
        assert!(blocks[0].contains("0.33 cup cream"));
        assert!(!blocks[0].contains("oil"));
        assert!(blocks[1].contains("33/100 cup oil"));
    }
    let one = "Cream\nIngredients:\n1 cup cream\n---\nSteps:\nMix.";
    assert_eq!(split_recipe_text(one).unwrap(), [one]);
    let many = std::iter::repeat_n(a, 51)
        .collect::<Vec<_>>()
        .join("\n---\n");
    assert!(split_recipe_text(&many).is_err());
}

#[test]
fn ordinary_and_embedded_imports_lowercase_tags_without_changing_steps() {
    let ordinary = paste::parse_recipe_input(
        "Soup\nTags: Dinner, DINNER, Quick\nIngredients:\n1 cup water\nSteps:\nMix Well.",
        NOW,
    )
    .unwrap();
    assert_eq!(
        ordinary.candidates[0].recipe.content.tags,
        vec!["dinner", "quick"]
    );
    assert_eq!(
        ordinary.candidates[0].recipe.content.steps,
        vec!["Mix Well."]
    );
    let mut value = embedded("33/100");
    value["keywords"] = json!("Dinner, DINNER, Quick");
    let candidate = web::map_json_ld(&value, "https://example.test/soup", NOW).unwrap();
    assert_eq!(candidate.recipe.content.tags, vec!["dinner", "quick"]);
    assert_eq!(candidate.recipe.content.steps, vec!["Mix."]);
}

#[test]
fn repeated_plain_title_fields_do_not_merge_and_intro_stays_with_first_candidate() {
    let a = "Title: First\nIngredients:\n1 cup flour\nSteps:\nMix.";
    let b = "Title: Second\nIngredients:\n2 cups milk\nSteps:\nStir.";
    let blocks = paste::split_recipe_text(&format!("{a}\n\n{b}")).unwrap();
    assert_eq!(blocks, [a, b]);
    let first = paste::parse_recipe_input(&blocks[0], NOW).unwrap();
    assert_eq!(first.candidates[0].recipe.content.title, "First");
    assert_eq!(first.candidates[0].recipe.content.ingredients.len(), 1);
    let intro = format!("Cookbook introduction\n# {a}\n# {b}");
    let blocks = paste::split_recipe_text(&intro).unwrap();
    assert_eq!(blocks.len(), 2);
    assert!(blocks[0].starts_with("Cookbook introduction"));
    assert!(!blocks[1].contains("flour"));
}

#[test]
fn units_normalize_on_all_new_input_paths_but_not_stored_reads() {
    for (raw, expected) in [
        ("TB", "tbsp"),
        ("T", "tbsp"),
        ("t", "tsp"),
        ("Tbs", "tbsp"),
        ("Tbsp", "tbsp"),
        ("tablespoons", "tbsp"),
        ("tsp.", "tsp"),
        ("teaspoons", "tsp"),
        ("c", "cup"),
        ("C", "cup"),
        ("lbs", "lb"),
        ("lb.", "lb"),
        ("pound", "lb"),
        ("pounds", "lb"),
        ("ounces", "oz"),
        ("ounce", "oz"),
        ("oz.", "oz"),
        ("tbsp.", "tbsp"),
        ("ML", "ml"),
        ("cloves", "clove"),
    ] {
        let line = format!("2 {raw} butter, melted");
        let pasted = paste::parse_ingredients(&line, "").unwrap();
        assert_eq!(pasted[0].ingredient.unit, expected, "{line}");
        assert_eq!(pasted[0].ingredient.prep_note, "melted");
        let mut ai = written("0.33");
        ai["ingredients"][0]["unit"] = json!(raw);
        assert_eq!(
            model::parse_ai_written(&ai.to_string(), NOW)
                .unwrap()
                .content
                .ingredients[0]
                .unit,
            expected
        );
        let mut r = sample();
        r.content.ingredients[0].unit = raw.into();
        let loaded = Recipe::from_json(&r.to_json().unwrap()).unwrap();
        assert_eq!(loaded.content.ingredients[0].unit, raw);
        let imported = text::import_text(&text::export_recipe(&r).unwrap(), NOW).unwrap();
        assert_eq!(
            imported.candidates[0].recipe.content.ingredients[0].unit,
            raw
        );
        let page = page(
            json!({"@type":"Recipe","name":"Units","recipeIngredient":[line],"recipeInstructions":["Mix."]}),
        );
        assert_eq!(
            web::inspect_page(&page, "https://example.com/recipe", NOW)
                .unwrap()
                .imports
                .candidates[0]
                .recipe
                .content
                .ingredients[0]
                .unit,
            expected
        );
    }
}

#[test]
fn size_words_are_names_on_manual_strict_and_ai_input() {
    for (raw, size) in [
        ("small", "small"),
        ("medium", "medium"),
        ("med.", "medium"),
        ("large", "large"),
        ("lg.", "large"),
    ] {
        let mut written = written("1");
        written["ingredients"][0]["unit"] = json!(raw);
        written["ingredients"][0]["name"] = json!("onion");
        let parsed = model::parse_ai_written(&written.to_string(), NOW).unwrap();
        let row = &parsed.content.ingredients[0];
        assert_eq!(row.unit, "");
        assert_eq!(row.name, format!("{size} onion"));
        let mut source = sample();
        source.content.ingredients[0].unit = raw.into();
        source.content.ingredients[0].name = "onion".into();
        let manual = source
            .content
            .parse_editor(&vec![Some("1".into()); source.content.ingredients.len()])
            .unwrap();
        assert_eq!(manual.ingredients[0].unit, "");
        assert_eq!(manual.ingredients[0].name, format!("{size} onion"));
        let imported = text::import_text(&text::export_recipe(&source).unwrap(), NOW).unwrap();
        assert_eq!(
            imported.candidates[0].recipe.content.ingredients[0].unit,
            raw
        );
        assert_eq!(
            imported.candidates[0].recipe.content.ingredients[0].name,
            "onion"
        );
        let pasted = paste::parse_ingredients(&format!("1 {raw} onion"), "").unwrap();
        assert_eq!(pasted[0].ingredient.unit, "");
        assert!(pasted[0].ingredient.name.ends_with("onion"));
    }
}
