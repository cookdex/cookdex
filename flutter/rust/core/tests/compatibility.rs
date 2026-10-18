use cookdex_core::{
    adapters::AppPaths,
    backup,
    recipe::text,
    services::{Operation, Service},
};
use std::path::PathBuf;

struct Root(PathBuf);
impl AppPaths for Root {
    fn private_root(&self) -> Result<PathBuf, String> {
        Ok(self.0.clone())
    }
}
impl Drop for Root {
    fn drop(&mut self) {
        let _ = std::fs::remove_dir_all(&self.0);
    }
}

#[test]
fn every_released_backup_format_restores_and_reexports() {
    for bytes in [
        include_bytes!("fixtures/compatibility/schema1.zip").as_slice(),
        include_bytes!("fixtures/compatibility/schema2.zip").as_slice(),
        include_bytes!("fixtures/compatibility/schema2-setup.zip").as_slice(),
    ] {
        let root =
            Root(std::env::temp_dir().join(format!("cookdex-compat-{}", uuid::Uuid::new_v4())));
        let service = Service::open(&root).unwrap();
        let op = Operation::default();
        let expected = backup::read(bytes).unwrap();
        let preview = service.preview_restore(bytes, &op).unwrap();
        let restored = service.restore(&preview, &op).unwrap();
        assert_eq!(restored.summaries.len(), expected.len());
        for recipe in expected {
            let actual = service.detail(&recipe.id).unwrap().unwrap();
            assert_eq!(actual.content, recipe.content);
            assert_eq!(
                backup::read(&backup::write(&[actual.clone()]).unwrap()).unwrap(),
                [actual]
            );
        }
    }
}

#[test]
fn historical_shared_text_still_imports() {
    let parsed = text::import_text(
        include_str!("fixtures/compatibility/legacy.txt"),
        "2026-01-01T00:00:00Z",
    )
    .unwrap();
    assert!(!parsed.candidates.is_empty());
    for candidate in parsed.candidates {
        candidate.recipe.content.validate().unwrap();
    }
}

#[test]
fn editor_save_tidies_names_but_keeps_spelling_amounts_and_notes() {
    let mut recipe = backup::read(include_bytes!("fixtures/compatibility/schema2.zip"))
        .unwrap()
        .remove(0);
    recipe.content.ingredients[0].name = "  Monterey   Jack  ".into();
    recipe.content.tags = vec!["  Family   Favorite ".into()];
    let parsed = recipe.content.parse_editor(&[None]).unwrap();
    assert_eq!(parsed.ingredients[0].name, "Monterey Jack");
    assert_eq!(parsed.tags, ["Family Favorite"]);
    assert_eq!(
        parsed.ingredients[0].amount,
        recipe.content.ingredients[0].amount
    );
    assert_eq!(
        parsed.ingredients[0].prep_note,
        recipe.content.ingredients[0].prep_note
    );
}
