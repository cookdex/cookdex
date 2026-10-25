use cookdex_core::provider::{self, Input, Mode, Photo};
use serde_json::{Value, json};

fn review(source: &str, mut output: Value, photo: bool) -> provider::AiReview {
    let input = Input {
        text: source.into(),
        source: String::new(),
        target_title: String::new(),
        photos: if photo {
            vec![Photo {
                mime_type: "image/jpeg".into(),
                bytes: vec![],
            }]
        } else {
            vec![]
        },
        mode: Mode::Recipe,
        existing_tags: vec![],
    };
    let mut base = json!({"status":"ok","reason":"","title":"Test recipe","description":"",
        "servings":"","prepTime":"","cookTime":"","totalTime":"","source":"","notes":"",
        "tags":[],"ingredients":[],"steps":[],"aiGuessedFields":[],"aiGuessedSteps":[]});
    for (key, value) in output.as_object_mut().unwrap() {
        base[key] = value.take();
    }
    let bytes = serde_json::to_vec(
        &json!({"status":"completed","steps":[{"type":"model_output",
        "content":[{"type":"text","text":base.to_string()}]}]}),
    )
    .unwrap();
    let (mut recipe, _) = provider::validated_response(&bytes).unwrap();
    provider::review_response(&bytes, &input, &mut recipe).unwrap()
}

#[test]
fn source_fields_override_both_missing_and_false_model_labels() {
    let r = review(
        "Serves 7\nPrep time: 12 minutes\nCook time: 18 minutes\nTotal time: 30 minutes\nTags: dinner, vegetarian\nWhisk until smooth.",
        json!({"servings":"7","prepTime":"12 min","cookTime":"18 min","totalTime":"30 min",
            "tags":["dinner","vegetarian"],"steps":["Whisk until smooth."],
            "aiGuessedFields":["servings","prepTime","cookTime","totalTime","tags"],"aiGuessedSteps":[0]}),
        false,
    );
    assert_eq!(r, provider::AiReview::default());
    let r = review(
        "7 apricots\nCook 18 minutes. This is a dinner story.",
        json!({"servings":"7","cookTime":"18 min","totalTime":"18 min","tags":["dinner"],
            "steps":["Whisk until smooth."]}),
        false,
    );
    assert_eq!(
        r.ai_guessed_fields,
        ["cookTime", "servings", "tags", "totalTime"]
    );
    assert_eq!(r.ai_guessed_steps, [0]);
}

#[test]
fn copied_units_and_whitespace_are_allowed_but_changed_facts_are_written() {
    let r = review(
        "1. Add 3 tablespoons nectar.\n2. Do not stir.\n3. Wait 8 minutes.",
        json!({"steps":["Add 3 tbsp nectar.","Do not stir.","Wait 9 min.","stir.","  Wait 8 min. "]}),
        false,
    );
    assert_eq!(r.ai_guessed_steps, [2, 3]);
}

#[test]
fn photo_labels_remain_model_owned_and_normalized() {
    let r = review(
        "Serves 7\nWhisk until smooth.",
        json!({"servings":"7","steps":["", "Whisk until smooth.","Bake."],
        "aiGuessedFields":["servings","servings","totalTime"],"aiGuessedSteps":[1,99]}),
        true,
    );
    assert_eq!(r.ai_guessed_fields, ["servings"]);
    assert_eq!(r.ai_guessed_steps, [0]);
}

#[test]
fn labeled_next_lines_and_yields_are_source_evidence() {
    let r = review(
        "Yield\n16 biscuits\nPrep Time\n14 minutes\n4 servings",
        json!({"servings":"16 biscuits","prepTime":"14 min"}),
        false,
    );
    assert!(r.ai_guessed_fields.is_empty());
    let r = review("Serves 6–9 people", json!({"servings":"6-9"}), false);
    assert!(r.ai_guessed_fields.is_empty());
    let r = review("Serves 16", json!({"servings":"6"}), false);
    assert_eq!(r.ai_guessed_fields, ["servings"]);
}

#[test]
fn embedded_recipe_fields_and_escaped_steps_are_compared_locally() {
    let html = r#"<script type="application/ld+json">{"@type":"Recipe","name":"Test recipe","recipeYield":"7 servings","prepTime":"PT12M","cookTime":"PT18M","totalTime":"PT30M","recipeCategory":"dinner","recipeIngredient":["3 tbsp nectar"],"recipeInstructions":[{"@type":"HowToStep","text":"Whisk until \"smooth\"."}]}</script>"#;
    let source = cookdex_core::recipe::web::ai_context(html).unwrap();
    let r = review(
        &source,
        json!({"servings":"7","prepTime":"12 min","cookTime":"18 min","totalTime":"30 min","tags":["dinner"],"steps":["Whisk until \"smooth\"."]}),
        false,
    );
    assert_eq!(r, provider::AiReview::default());
}

#[test]
fn single_letter_units_and_abbreviation_periods_are_copied() {
    let r = review(
        "Add 2 T syrup. Add 3 t. nectar. Stir.\nWait 8 minutes. Cool.",
        json!({"steps":["Add 2 tbsp syrup.","Add 3 tsp nectar.","Stir.","Wait 8 min.","Cool."]}),
        false,
    );
    assert!(r.ai_guessed_steps.is_empty(), "{r:?}");
}

#[test]
fn rendered_time_number_and_unit_can_be_on_separate_lines() {
    let r = review(
        "Prep Time22\nminutes\nminutes\nCook Time\n38\nminutes\nTotal Time 1\nhour\nYield5 servings\nCourseDinner",
        json!({"servings":"5","prepTime":"22 min","cookTime":"38 min","totalTime":"1 hr","tags":["dinner"]}),
        false,
    );
    assert_eq!(r, provider::AiReview::default());
}

#[test]
fn a_shorter_suffix_or_prefix_is_not_a_complete_copied_instruction() {
    let r = review(
        "Do not cover. Whisk then chill.",
        json!({"steps":["cover.","Whisk","Whisk then chill.","Do not cover."]}),
        false,
    );
    assert_eq!(r.ai_guessed_steps, [0, 1]);
}

#[test]
fn fraction_glyph_typography_does_not_change_a_copied_number() {
    let r = review(
        "Use ⅝ of the glaze. Add 1½ cups nectar.",
        json!({"steps":["Use 5/8 of the glaze.","Add 1 1/2 cups nectar.","Use 3/5 of the glaze."]}),
        false,
    );
    assert_eq!(r.ai_guessed_steps, [2]);
}
