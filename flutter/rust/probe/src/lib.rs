//! Disposable C1/C2 load probe, NOT the application bridge (FRB is C3).
use cookdex_core::{adapters::AppPaths, session::Session, storage::Book};
use std::{
    ffi::{CStr, c_char},
    path::{Path, PathBuf},
};

struct Paths(PathBuf);
impl AppPaths for Paths {
    fn private_root(&self) -> Result<PathBuf, String> {
        Ok(self.0.clone())
    }
}

/// Runs synthetic SQLite/history work only inside a newly created directory.
pub fn verify(parent: &Path) -> Result<(), String> {
    if !parent.is_absolute() {
        return Err("Absolute temporary root required".into());
    }
    let root = parent.join(format!("cookdex-c1-{}", uuid::Uuid::new_v4()));
    std::fs::create_dir(&root).map_err(|e| e.to_string())?;
    let result = verify_inner(&root);
    let cleanup = std::fs::remove_dir_all(&root).map_err(|e| e.to_string());
    result.and(cleanup)
}

fn verify_inner(root: &Path) -> Result<(), String> {
    verify_recipe_rules().map_err(|e| e.to_string())?;
    let paths = Paths(root.to_owned());
    let session = Session::open(&paths)?;
    let initial = session.load()?;
    if initial.generation != 0 || initial.book != Book::default() {
        return Err("Not fresh".into());
    }
    let id = session.device_id()?;
    let book: Book = serde_json::from_str(include_str!("../../core/tests/native-fixture.json"))
        .map_err(|e| e.to_string())?;
    if session.save(0, &book, "synthetic-first")? != 1 {
        return Err("Bad generation".into());
    }
    if !session
        .save(0, &Book::default(), "stale")
        .is_err_and(|e| e.contains("STALE_WRITE"))
    {
        return Err("Stale save accepted".into());
    }
    let mut bad = book.clone();
    bad.recipes[0]["ingredients"][0]["amount"]["denominator"] = 0.into();
    if session.save(1, &bad, "invalid").is_ok() {
        return Err("Invalid save accepted".into());
    }
    session.foreground(true)?; // Fresh sync is disabled: no listener or peer contact.
    session.foreground(false)?;
    drop(session);
    let session = Session::open(&paths)?;
    let loaded = session.load()?;
    if session.device_id()? != id || loaded.generation != 1 || loaded.book != book {
        return Err("Persistence/rollback failure".into());
    }
    session.save(1, &Book::default(), "synthetic-delete")?;
    session.save(2, &book, "synthetic-recover")?;
    if session.load()?.book != book {
        return Err("Recovery failure".into());
    }
    Ok(())
}

fn verify_recipe_rules() -> Result<(), cookdex_core::recipe::RuleError> {
    use cookdex_core::recipe::{Amount, AmountInput, Recipe, paste, text, web};
    let now = "2026-01-02T03:04:05.000Z";
    let imports = paste::parse_recipe_input(
        "Synthetic C2 soup\nIngredients:\n0.33 cup oil\n33/100 cup cream\nSteps:\nMix.",
        now,
    )?;
    let recipe = imports.select(0)?.0.recipe;
    let copy = Recipe::from_json(&recipe.to_json()?)?;
    let reread = text::import_text(&text::export_recipe(&copy)?, now)?
        .select(0)?
        .0
        .recipe;
    let page = web::inspect_page(
        r#"<script type="application/ld+json">{"@type":"Recipe","name":"C2 page","recipeIngredient":["0.3 cup water"],"recipeInstructions":["Mix."]}</script>"#,
        "https://example.test",
        now,
    )?;
    if recipe.content.ingredients[0].amount.text() != "1/3"
        || copy.content.ingredients[1].amount.text() != "33/100"
        || Amount::from_input(AmountInput::Unchanged(copy.content.ingredients[1].amount))?.text()
            != "33/100"
        || reread.content != recipe.content
        || page.imports.select(0)?.0.recipe.content.ingredients[0]
            .amount
            .text()
            != "3/10"
    {
        return Err(cookdex_core::recipe::RuleError(
            "C2 recipe rule probe failed.",
        ));
    }
    Ok(())
}

/// # Safety
/// `parent` must point to a valid NUL-terminated UTF-8 string for this call.
/// Returns 0 on success, 1 on verification failure, 2 on panic/invalid argument.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn cookdex_c1_probe(parent: *const c_char) -> i32 {
    if parent.is_null() {
        return 2;
    }
    std::panic::catch_unwind(|| {
        let Ok(parent) = (unsafe { CStr::from_ptr(parent) }).to_str() else {
            return 2;
        };
        if verify(Path::new(parent)).is_ok() {
            0
        } else {
            1
        }
    })
    .unwrap_or(2)
}

#[cfg(test)]
mod tests {
    #[test]
    fn disposable_probe() {
        super::verify(&std::env::temp_dir()).unwrap();
    }
}
