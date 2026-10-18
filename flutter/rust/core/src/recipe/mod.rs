//! Pure C2 recipe rules. No storage, network, provider, or batch-save API.
pub mod amount;
pub mod duration;
pub mod model;
pub mod paste;
pub mod repair;
pub mod scaling;
pub mod text;
pub mod units;
pub mod web;

pub use amount::{Amount, AmountInput, Rational};
pub use model::{Ingredient, Recipe, RecipeContent, RecipeId, WrittenIngredient, WrittenRecipe};

pub const MAX_INPUT_BYTES: usize = 5 * 1024 * 1024;
pub const MAX_COLLECTION_BYTES: usize = 32 * 1024 * 1024;
pub const MAX_ITEMS: usize = 10_000;
pub const MAX_CANDIDATES: usize = 50;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RuleError(pub &'static str);
impl std::fmt::Display for RuleError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str(self.0)
    }
}
impl std::error::Error for RuleError {}
pub type Result<T> = std::result::Result<T, RuleError>;
pub(crate) fn error(message: &'static str) -> RuleError {
    RuleError(message)
}
pub(crate) fn bounded(text: &str, max: usize) -> Result<()> {
    // Count UTF-8 bytes, including encoded non-ASCII input, before parsing/allocation.
    if text.len() > max {
        Err(error("Text exceeds its size limit."))
    } else {
        Ok(())
    }
}
pub(crate) fn rx(pattern: &'static str) -> &'static regex::Regex {
    use std::{
        collections::HashMap,
        sync::{Mutex, OnceLock},
    };
    static CACHE: OnceLock<Mutex<HashMap<&'static str, &'static regex::Regex>>> = OnceLock::new();
    let mut cache = CACHE
        .get_or_init(Default::default)
        .lock()
        .expect("regex cache");
    cache
        .entry(pattern)
        .or_insert_with(|| Box::leak(Box::new(regex::Regex::new(pattern).expect("static regex"))))
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Candidate {
    pub recipe: Recipe,
    pub warnings: Vec<String>,
    pub ingredient_sources: Vec<String>,
}
#[derive(Debug, Clone, PartialEq, Eq, Default)]
pub struct ImportCandidates {
    pub candidates: Vec<Candidate>,
    pub warnings: Vec<String>,
    pub ordinary: bool,
}
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SelectedRecipeDraft(pub Candidate);
impl ImportCandidates {
    /// Select exactly one draft. Selection does not save anything.
    pub fn select(&self, index: usize) -> Result<SelectedRecipeDraft> {
        self.candidates
            .get(index)
            .cloned()
            .map(SelectedRecipeDraft)
            .ok_or_else(|| error("Choose an available recipe."))
    }
}
