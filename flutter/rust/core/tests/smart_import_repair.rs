use cookdex_core::{
    provider,
    recipe::{self, Amount},
};
use serde_json::{Value, json};
const NOW: &str = "2026-10-09T12:00:00Z";
fn input() -> provider::Input {
    provider::Input {
        text: "source".into(),
        source: String::new(),
        target_title: String::new(),
        photos: vec![],
        mode: provider::Mode::Recipe,
        existing_tags: vec!["Family Favorite".into()],
    }
}
fn written() -> Value {
    json!({"status":"ok","reason":"","title":"Rolls","description":"","servings":"12","prepTime":"","cookTime":"","totalTime":"","source":"","notes":"","tags":[],"ingredients":[{"amount":"4 -5","unit":"cups","name":"flour","prepNote":"sifted","section":"","optional":false}],"steps":["Mix."]})
}
fn envelope(v: Value) -> Vec<u8> {
    serde_json::to_vec(&json!({"status":"completed","steps":[{"type":"model_output","content":[{"type":"text","text":v.to_string()}]}]})).unwrap()
}
#[test]
fn unsupported_amounts_repair_in_ai_but_fail_exact_text() {
    for amount in ["one generous handful", "0", "-2", "5-4"] {
        let mut v = written();
        v["ingredients"][0]["amount"] = json!(amount);
        let (r, w) = provider::validated_response(&envelope(v)).unwrap();
        let row = &r.content.ingredients[0];
        assert_eq!(row.amount, Amount::Unspecified);
        assert_eq!(row.unit, "");
        assert_eq!(row.name, "flour");
        assert_eq!(row.prep_note, format!("{amount} cups; sifted"));
        assert!(
            w.iter()
                .any(|s| s.contains("flour") && s.contains("could not be parsed"))
        );
        let text = recipe::text::export_recipe(&r)
            .unwrap()
            .replace("-  |  | flour", &format!("- {amount} | cups | flour"));
        assert!(recipe::text::import_text(&text, NOW).is_err());
    }
}
#[test]
fn corrupt_fields_never_discard_usable_siblings() {
    let mut v = written();
    v["source"] = json!("javascript:bad");
    v["description"] = json!({"bad":true});
    v["servings"] = json!(12);
    v["title"] = json!("a".repeat(200));
    v["tags"] = json!([3, "dinner"]);
    v["steps"] = json!([null, "Mix."]);
    v["ingredients"].as_array_mut().unwrap().extend([
        json!(null),
        json!({"name":"salt","amount":"to taste","optional":"bad"}),
    ]);
    let (r, w) = provider::validated_response(&envelope(v)).unwrap();
    assert_eq!(r.content.title.len(), 160);
    assert_eq!(r.content.steps, ["Mix."]);
    assert_eq!(r.content.ingredients.len(), 2);
    assert!(r.content.source.is_empty());
    assert_eq!(r.content.servings, "12");
    assert!(w.len() > 6);
    r.validate().unwrap();
}
#[test]
fn only_empty_content_fails_and_status_and_truncation_explain_why() {
    for v in [
        json!({"title":"Only title"}),
        json!({"steps":["Mix."]}),
        json!({"ingredients":["salt"]}),
    ] {
        assert!(provider::validated_response(&envelope(v)).is_ok());
    }
    assert_eq!(
        provider::validated_response(&envelope(json!({})))
            .unwrap_err()
            .message,
        "Nothing usable came back: no title, no ingredients and no steps."
    );
    for (status, phrase) in [
        ("unreadable", "could not read"),
        ("not_a_recipe", "found no recipe"),
        ("retrieval_failed", "could not retrieve"),
    ] {
        let e = provider::validated_response(&envelope(
            json!({"status":status,"reason":"specific reason"}),
        ))
        .unwrap_err();
        assert!(e.message.contains(phrase) && e.message.contains("specific reason"));
        assert!(!e.retryable);
    }
    let e = provider::validated_response(br#"{"status":"incomplete","steps":[]}"#).unwrap_err();
    assert!(e.message.contains("cut off"));
}
#[test]
fn malformed_guesses_are_ignored_and_tags_still_filtered() {
    for bad in [Value::Null, json!("servings"), json!([0]), json!({})] {
        let mut v = written();
        v["aiGuessedFields"] = bad;
        v["aiGuessedSteps"] = json!([0]);
        v["tags"] = json!(["invented", "dinner"]);
        let bytes = envelope(v);
        let (mut r, _) = provider::validated_response(&bytes).unwrap();
        let review = provider::review_response(&bytes, &input(), &mut r).unwrap();
        assert_eq!(review, provider::AiReview::default());
        assert_eq!(r.content.tags, ["dinner"]);
    }
}
#[test]
fn shared_rules_cannot_diverge_and_retry_contains_specific_problem() {
    let i = input();
    let tags = provider::allowed_tags(&i);
    let copy = provider::copy_prompt(&tags);
    for rule in [
        "can, jar, bottle, box, bag, package",
        "unit (14 oz) cans, name diced tomatoes",
        "unit (16 oz) jar, name salsa",
        "Preserve the size exactly",
    ] {
        assert!(copy.contains(rule));
    }
    for (mode, photos) in [
        (provider::Mode::Recipe, false),
        (provider::Mode::Recipe, true),
        (provider::Mode::UrlRecipe, false),
    ] {
        let prompt = provider::json_prompt(&mode, photos, &tags);
        assert_eq!(
            &prompt[..provider::INSTRUCTION.len()],
            &copy[..provider::INSTRUCTION.len()]
        );
        assert!(prompt.starts_with(provider::INSTRUCTION));
        assert!(copy.starts_with(provider::INSTRUCTION));
        assert!(prompt.contains("family favorite") && copy.contains("family favorite"));
        assert!(!prompt.contains("return an empty object"));
    }
    let body: Value = serde_json::from_slice(
        &provider::request_with_problems(
            &i,
            "gemini-3.5-flash-lite",
            Some("The reply was cut off before the recipe was complete."),
        )
        .unwrap(),
    )
    .unwrap();
    assert!(
        body["system_instruction"]
            .as_str()
            .unwrap()
            .contains("cut off before the recipe")
    );
    assert_eq!(body["generation_config"]["max_output_tokens"], 65536);
    assert_eq!(body["generation_config"]["thinking_level"], "minimal");
    assert_eq!(
        body["response_format"]["schema"]["properties"]["status"]["enum"],
        json!(["ok", "unreadable", "not_a_recipe", "retrieval_failed"])
    );
}

#[test]
fn sized_container_reply_keeps_product_name_and_exact_size() {
    let mut v = written();
    v["ingredients"] = json!([
        {"name":"diced tomatoes","amount":"2","unit":"(14 oz) cans","prepNote":"drained","section":"","optional":false},
        {"name":"salsa","amount":"1","unit":"(16 oz) jar","prepNote":"","section":"","optional":false},
        {"name":"broth","amount":"2","unit":"(250 ml) bottles","prepNote":"","section":"","optional":false}
    ]);
    let (recipe, _) = provider::validated_response(&envelope(v)).unwrap();
    let rows = &recipe.content.ingredients;
    assert_eq!(rows[0].name, "diced tomatoes");
    assert_eq!(rows[0].prep_note, "drained");
    assert_eq!(
        rows.iter().map(|r| r.unit.as_str()).collect::<Vec<_>>(),
        ["(14 oz) cans", "(16 oz) jar", "(250 ml) bottles"]
    );
    assert_eq!(rows[0].amount.text(), "2");
}

#[test]
fn import_repairs_explicit_preparation_count_and_optional_markers() {
    let mut v = written();
    v["ingredients"] = json!([
        {"name":"grated medium cheese","amount":"1","unit":"cup","prepNote":"for topping","section":"","optional":false},
        {"name":"warm milk","amount":"1","unit":"cup","prepNote":"","section":"","optional":false},
        {"name":"large eggs","amount":"2","unit":"eggs","prepNote":"","section":"","optional":false},
        {"name":"chopped onion","amount":"1","unit":"each","prepNote":"","section":"Optional topping","optional":false},
        {"name":"melted butter","amount":"1","unit":"tbsp","prepNote":"","section":"Glaze (optional)","optional":false}
    ]);
    let (r, _) = provider::validated_response(&envelope(v)).unwrap();
    let rows = &r.content.ingredients;
    assert_eq!(
        (&*rows[0].name, &*rows[0].prep_note),
        ("medium cheese", "grated; for topping")
    );
    assert_eq!((&*rows[1].name, &*rows[1].prep_note), ("milk", "warm"));
    assert_eq!(rows[2].name, "large eggs");
    assert!(rows[2].unit.is_empty());
    assert!(rows[3].unit.is_empty() && rows[3].optional);
    assert_eq!(rows[3].prep_note, "chopped");
    assert_eq!((&*rows[4].name, &*rows[4].prep_note), ("butter", "melted"));
    assert!(rows[4].optional);
}

#[test]
fn durations_are_readable_on_every_new_import_route() {
    let mut v = written();
    v["prepTime"] = json!("PT22M");
    v["cookTime"] = json!("PT1H30M");
    v["totalTime"] = json!("PT1H52M");
    let (ai, _) = provider::validated_response(&envelope(v)).unwrap();
    let check = |r: &recipe::Recipe| {
        assert_eq!(r.content.prep_time, "22 min");
        assert_eq!(r.content.cook_time, "1 hr 30 min");
        assert_eq!(r.content.total_time, "1 hr 52 min");
    };
    check(&ai); // Text, link and photo JSON all share this provider boundary.
    let text = recipe::text::export_recipe(&ai)
        .unwrap()
        .replace("22 min", "PT22M")
        .replace("1 hr 30 min", "PT1H30M")
        .replace("1 hr 52 min", "PT1H52M");
    let exact = recipe::text::import_text(&text, NOW).unwrap();
    assert_eq!(exact.candidates[0].recipe.content.prep_time, "PT22M");
    assert_eq!(exact.candidates[0].recipe.content.cook_time, "PT1H30M");
    assert_eq!(exact.candidates[0].recipe.content.total_time, "PT1H52M");
    check(&recipe::paste::parse_recipe_input("Soup\nPrep time: PT22M\nCook time: PT1H30M\nTotal time: PT1H52M\nIngredients:\n1 cup broth\nSteps:\n1. Simmer.", NOW).unwrap().candidates[0].recipe);
    check(&recipe::web::map_json_ld(&json!({"name":"Soup","prepTime":"PT22M","cookTime":"PT1H30M","totalTime":"PT1H52M","recipeIngredient":["1 cup broth"],"recipeInstructions":["Simmer."]}), "", NOW).unwrap().recipe);
    // Canonical deserialization is deliberately not an import rewrite.
    let stored = serde_json::to_value(&ai).unwrap();
    let mut stored_iso = stored;
    stored_iso["prepTime"] = json!("PT22M");
    let restored: recipe::Recipe = serde_json::from_value(stored_iso).unwrap();
    assert_eq!(restored.content.prep_time, "PT22M");
}

#[test]
fn normalization_growth_is_repaired_before_strict_validation() {
    let mut v = written();
    v["tags"] = json!(["İ".repeat(300)]);
    v["ingredients"][0]["name"] = json!("x".repeat(2000));
    v["ingredients"][0]["unit"] = json!("medium");
    v["ingredients"][0]["amount"] = json!("1");
    let (recipe, warnings) = provider::validated_response(&envelope(v.clone())).unwrap();
    recipe.validate().unwrap();
    assert_eq!(recipe.content.tags[0].encode_utf16().count(), 300);
    assert_eq!(recipe.content.ingredients[0].name.len(), 2000);
    assert!(warnings.iter().any(|w| w.contains("Normalized tag")));
    v["ingredients"][0]["unit"] = json!("İ".repeat(2000));
    let (recipe, _) = provider::validated_response(&envelope(v)).unwrap();
    recipe.validate().unwrap();
}

#[test]
fn page_context_keeps_body_after_tag_like_script_strings() {
    let html = r#"<title>Soup</title><script>document.write('<script src=\"ads.js\">');</script><style>.x:before{content:'<style>'}</style><nav>menu<script>const x='<script>';</script></nav><main><h1>Soup</h1><p>2 cups broth</p><p>Simmer 10 minutes.</p></main>"#;
    let text = recipe::web::readable_text(html).unwrap();
    assert!(text.contains("2 cups broth"));
    assert!(text.contains("Simmer 10 minutes."));
    assert!(!text.contains("document.write"));
    assert!(!text.contains("menu"));
    let context = recipe::web::ai_context(html).unwrap();
    assert!(context.contains("2 cups broth"));
}

#[test]
fn implicit_sized_container_reply_repairs_only_unambiguous_singular_forms() {
    let mut v = written();
    v["ingredients"] = json!([
        {"name":"salsa verde","amount":"","unit":"(16 oz) jar","prepNote":"","section":"","optional":false},
        {"name":"16 oz jar of salsa verde","amount":"","unit":"","prepNote":"","section":"","optional":false},
        {"name":"jar of salsa verde","amount":"16","unit":"oz","prepNote":"","section":"","optional":false},
        {"name":"salsa verde","amount":"2","unit":"(16 oz) jars","prepNote":"","section":"","optional":false},
        {"name":"salsa verde","amount":"","unit":"(16 oz) jars","prepNote":"","section":"","optional":false},
        {"name":"salsa verde","amount":"to taste","unit":"(16 oz) jar","prepNote":"","section":"","optional":false}
    ]);
    let (recipe, _) = provider::validated_response(&envelope(v)).unwrap();
    for row in &recipe.content.ingredients[..3] {
        assert_eq!(row.amount.text(), "1");
        assert_eq!(row.unit, "(16 oz) jar");
        assert_eq!(row.name, "salsa verde");
    }
    assert_eq!(recipe.content.ingredients[3].amount.text(), "2");
    assert_eq!(recipe.content.ingredients[4].amount.text(), "");
    assert_eq!(recipe.content.ingredients[5].amount.text(), "to taste");
}

#[test]
fn implicit_sized_container_accepts_container_case_but_not_a_plural() {
    for (unit, expected) in [
        ("(16 OZ) Jar", "1"),
        ("(16 OZ) JAR", "1"),
        ("(16 OZ) JARS", ""),
    ] {
        let mut v = written();
        v["ingredients"] = json!([{"name":"salsa verde","amount":"","unit":unit,"prepNote":"","section":"","optional":false}]);
        let (recipe, _) = provider::validated_response(&envelope(v)).unwrap();
        assert_eq!(recipe.content.ingredients[0].amount.text(), expected);
        assert!(recipe.content.ingredients[0].unit.starts_with("(16 OZ)"));
    }
}
