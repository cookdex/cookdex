use cookdex_core::{
    adapters::AppPaths,
    backup,
    recipe::{self, Recipe, text},
    services::{DuplicateChoice, Operation, Service},
};
use serde_json::Value;
const NOW: &str = "2026-01-02T03:04:05Z";
struct Root(std::path::PathBuf);
impl AppPaths for Root {
    fn private_root(&self) -> Result<std::path::PathBuf, String> {
        Ok(self.0.clone())
    }
}
impl Drop for Root {
    fn drop(&mut self) {
        let _ = std::fs::remove_dir_all(&self.0);
    }
}
fn samples() -> Vec<Recipe> {
    let corpus: Value =
        serde_json::from_str(include_str!("../../../../tests/fixtures/corpus.json")).unwrap();
    let mut recipes: Vec<_> = corpus["recipes"]
        .as_array()
        .unwrap()
        .iter()
        .map(|v| Recipe::from_json(&serde_json::to_vec(v).unwrap()).unwrap())
        .collect();
    recipes.extend(backup::read(include_bytes!("fixtures/compatibility/schema2.zip")).unwrap());
    recipes
}
#[test]
fn entire_synthetic_library_one_file_exact_round_trip_and_new_records() {
    let recipes = samples();
    let output = text::export_cookbook(&recipes).unwrap();
    let parsed = text::import_text(&output, NOW).unwrap();
    assert_eq!(parsed.candidates.len(), recipes.len());
    let root = Root(std::env::temp_dir().join(format!("cookdex-text-{}", uuid::Uuid::new_v4())));
    let service = Service::open(&root).unwrap();
    let mut generation = service.snapshot().unwrap().generation;
    for (original, candidate) in recipes.iter().zip(parsed.candidates) {
        assert_eq!(original.content, candidate.recipe.content);
        assert_ne!(original.id, candidate.recipe.id);
        assert!(!candidate.recipe.favorite);
        let snapshot = service
            .import_one(
                generation,
                candidate.recipe.content.clone(),
                Some(DuplicateChoice::KeepBoth),
                &Operation::default(),
            )
            .unwrap();
        generation = snapshot.generation;
        let saved = snapshot
            .summaries
            .iter()
            .find_map(|r| {
                let recipe = service.detail(&r.id).unwrap().unwrap();
                (recipe.content == original.content).then_some(recipe)
            })
            .unwrap();
        assert_eq!(saved.content, original.content);
        assert!(!saved.favorite);
    }
}
#[test]
fn fixed_v1_samples_are_read_in_full_suite() {
    for (input, count) in [
        (include_str!("fixtures/compatibility/text-v1-single.txt"), 1),
        (include_str!("fixtures/compatibility/text-v1-multi.txt"), 2),
    ] {
        let parsed = text::import_text(input, NOW).unwrap();
        assert_eq!(parsed.candidates.len(), count);
        for candidate in parsed.candidates {
            candidate.recipe.validate().unwrap();
        }
    }
}
#[test]
fn transport_whitespace_and_word_wrapping_are_tolerated() {
    let input = include_str!("fixtures/compatibility/text-v1-multi.txt");
    let expected = text::import_text(input, NOW).unwrap();
    let wrapped = input
        .replace(
            "made-up recipe for interchange",
            "made-up recipe\nfor interchange",
        )
        .replace("white beans | rinsed", "white beans |\nrinsed")
        .replace(
            "Mix the beans and warm gently.",
            "Mix the beans and\nwarm gently.",
        );
    for variant in [
        format!("\u{feff}{input}"),
        input.replace('\n', "\r\n"),
        input.replace('\n', "\n\n"),
        format!(
            "\n\u{feff}{}",
            wrapped
                .lines()
                .map(|line| format!("{line}   "))
                .collect::<Vec<_>>()
                .join("\r\n")
        ),
    ] {
        let actual = text::import_text(&variant, NOW).unwrap();
        assert_eq!(actual.candidates.len(), expected.candidates.len());
        for (a, e) in actual.candidates.iter().zip(&expected.candidates) {
            assert_eq!(a.recipe.content, e.recipe.content);
        }
    }
}
#[test]
fn malformed_or_truncated_never_returns_a_partial_recipe() {
    let input = include_str!("fixtures/compatibility/text-v1-multi.txt");
    for variant in [
        input[..input.len() - 8].to_string(),
        input.replace("Tags: []", "Tags: [broken]"),
        input.replace(" | no", " | invalid"),
        "Ordinary recipe text".into(),
        "x".repeat(recipe::MAX_INPUT_BYTES + 1),
    ] {
        assert!(text::import_text(&variant, NOW).is_err());
    }
}
#[test]
fn valid_empty_optional_and_escaped_fields_stay_exact() {
    let mut recipe = samples().remove(0);
    recipe.content.description.clear();
    recipe.content.source.clear();
    recipe.content.servings.clear();
    recipe.content.steps = vec!["".into(), "  keep spacing  ".into()];
    recipe.content.tags = vec!["".into(), "MiXeD".into(), "MiXeD".into()];
    recipe.content.ingredients[0].unit = "TB".into();
    recipe.content.ingredients[0].name = "  white  beans  ".into();
    recipe.content.ingredients[0].prep_note = "  chopped  ".into();
    recipe.content.ingredients[0].section = "  Sauce  ".into();
    let parsed = text::import_text(&text::export_recipe(&recipe).unwrap(), NOW).unwrap();
    assert_eq!(recipe.content, parsed.candidates[0].recipe.content);
}

#[test]
fn empty_step_with_transport_padding_remains_a_complete_recipe() {
    let mut r = samples().remove(0);
    r.content.steps = vec![String::new(), "Serve.".into()];
    let exported = text::export_recipe(&r).unwrap();
    let padded = exported
        .lines()
        .map(|line| format!("{line}   "))
        .collect::<Vec<_>>()
        .join("\n");
    let result = text::import_text(&padded, NOW).unwrap();
    assert_eq!(result.candidates[0].recipe.content, r.content);
}
