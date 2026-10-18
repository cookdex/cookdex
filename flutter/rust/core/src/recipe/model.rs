use super::{Amount, MAX_COLLECTION_BYTES, MAX_INPUT_BYTES, MAX_ITEMS, Result, bounded, error};
use serde::{Deserialize, Serialize};
use std::collections::{HashMap, HashSet};

#[derive(Debug, Clone, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(transparent)]
pub struct RecipeId(pub String);
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct Ingredient {
    pub amount: Amount,
    pub unit: String,
    pub name: String,
    pub prep_note: String,
    pub optional: bool,
    pub section: String,
}
/// Raw amounts from a new editor field or extraction, never canonical JSON.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct WrittenIngredient {
    pub amount: String,
    pub unit: String,
    pub name: String,
    pub prep_note: String,
    pub optional: bool,
    pub section: String,
}
#[derive(Debug, Clone, PartialEq, Eq, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct RecipeContent<I = Ingredient> {
    pub title: String,
    pub description: String,
    pub servings: String,
    pub prep_time: String,
    pub cook_time: String,
    pub total_time: String,
    pub source: String,
    pub tags: Vec<String>,
    pub notes: String,
    pub ingredients: Vec<I>,
    pub steps: Vec<String>,
}
pub type WrittenRecipe = RecipeContent<WrittenIngredient>;

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Recipe {
    pub schema_version: u32,
    pub id: RecipeId,
    pub favorite: bool,
    pub created_at: String,
    pub updated_at: String,
    pub revision: u64,
    #[serde(flatten)]
    pub content: RecipeContent,
}
pub(crate) fn field(value: &str, max: usize) -> Result<()> {
    // Match schema-1 readers' UTF-16 field bounds; overall caps count bytes.
    if value.encode_utf16().count() > max {
        Err(error("Recipe field exceeds its limit."))
    } else {
        Ok(())
    }
}
pub fn safe_source(value: &str) -> bool {
    url::Url::parse(value)
        .is_ok_and(|url| matches!(url.scheme(), "http" | "https") && url.host_str().is_some())
}
pub fn normalize_name(value: &str) -> String {
    value
        .split_whitespace()
        .collect::<Vec<_>>()
        .join(" ")
        .to_lowercase()
}
impl Ingredient {
    /// Recover only the entire first semicolon-delimited prep segment, with
    /// a range and optionally a known unit. Never guess from sizes or prose.
    fn recover_stashed_range(&mut self) {
        if self.amount != Amount::Unspecified {
            return;
        }
        let (prefix, rest) = self
            .prep_note
            .split_once(';')
            .unwrap_or((&self.prep_note, ""));
        static PREFIX: std::sync::LazyLock<regex::Regex> = std::sync::LazyLock::new(|| {
            regex::Regex::new(&format!(
                r"(?i)^\s*({0}\s*(?:–|-|\s+to\s+)\s*{0})(?:\s+([a-zA-Z.]+))?\s*$",
                super::amount::NUMBER_PATTERN
            ))
            .unwrap()
        });
        let Some(c) = PREFIX.captures(prefix) else {
            return;
        };
        let Ok(amount) = Amount::parse_new(&c[1]) else {
            return;
        };
        let recovered_unit = c
            .get(2)
            .map(|m| super::units::normalize(m.as_str()))
            .unwrap_or_default();
        if !recovered_unit.is_empty()
            && super::units::leading_unit(&format!("{recovered_unit} ingredient")).is_none()
        {
            return;
        }
        if !self.unit.is_empty()
            && !recovered_unit.is_empty()
            && super::units::normalize(&self.unit) != recovered_unit
        {
            return;
        }
        self.amount = amount;
        if self.unit.is_empty() {
            self.unit = recovered_unit;
        }
        self.prep_note = rest.trim().into();
    }
    pub fn validate(&self) -> Result<()> {
        self.amount.validate()?;
        for value in [&self.unit, &self.name, &self.prep_note, &self.section] {
            field(value, 2000)?;
        }
        if self.name.trim().is_empty() {
            return Err(error("Each ingredient needs a name."));
        }
        Ok(())
    }
    pub fn text(&self) -> String {
        let mut result = [
            self.amount.text(),
            super::units::display(&self.unit, self.amount),
            self.name.clone(),
        ]
        .into_iter()
        .filter(|s| !s.is_empty())
        .collect::<Vec<_>>()
        .join(" ");
        if !self.prep_note.is_empty() {
            result.push_str(&format!(", {}", self.prep_note));
        }
        result
    }
}
impl WrittenIngredient {
    pub fn parse(&self) -> Result<Ingredient> {
        for value in [
            &self.amount,
            &self.unit,
            &self.name,
            &self.prep_note,
            &self.section,
        ] {
            field(value, 2000)?;
        }
        let (unit, name) = super::units::normalize_ingredient(&self.unit, &self.name);
        let result = Ingredient {
            amount: Amount::parse_new(&self.amount)?,
            unit,
            name,
            prep_note: self.prep_note.trim().into(),
            optional: self.optional,
            section: self.section.trim().into(),
        };
        result.validate()?;
        Ok(result)
    }
}
impl<I> RecipeContent<I> {
    fn validate_fields(&self) -> Result<()> {
        field(&self.title, 160)?;
        if self.title.trim().is_empty() {
            return Err(error("Give your recipe a name."));
        }
        field(&self.description, 2000)?;
        field(&self.source, 2000)?;
        field(&self.notes, 20000)?;
        for value in [
            &self.servings,
            &self.prep_time,
            &self.cook_time,
            &self.total_time,
        ] {
            field(value, 80)?;
        }
        if self.tags.len() > MAX_ITEMS
            || self.ingredients.len() > MAX_ITEMS
            || self.steps.len() > MAX_ITEMS
        {
            return Err(error("Recipe list exceeds its limit."));
        }
        for tag in &self.tags {
            field(tag, 300)?;
        }
        for step in &self.steps {
            field(step, 30000)?;
        }
        Ok(())
    }
}
impl RecipeContent {
    /// Normalize raw editor text while retaining canonical amounts on untouched
    /// rows. A null input is deliberately distinct from an edited empty amount.
    pub fn parse_editor(&self, amount_inputs: &[Option<String>]) -> Result<Self> {
        self.validate_fields()?;
        if amount_inputs.len() != self.ingredients.len() {
            return Err(error("Ingredient amounts do not match the editor rows."));
        }
        let written = WrittenRecipe {
            title: self.title.clone(),
            description: self.description.clone(),
            servings: self.servings.clone(),
            prep_time: self.prep_time.clone(),
            cook_time: self.cook_time.clone(),
            total_time: self.total_time.clone(),
            source: self.source.clone(),
            tags: self.tags.clone(),
            notes: self.notes.clone(),
            steps: self.steps.clone(),
            ingredients: self
                .ingredients
                .iter()
                .zip(amount_inputs)
                .map(|(row, input)| WrittenIngredient {
                    amount: input.clone().unwrap_or_default(),
                    unit: row.unit.clone(),
                    name: row.name.clone(),
                    prep_note: row.prep_note.clone(),
                    optional: row.optional,
                    section: row.section.clone(),
                })
                .collect(),
        };
        let mut parsed = written.parse()?;
        // Manual/reviewed tag spellings are deliberate; imports still use their
        // existing lowercase extraction rules before reaching the editor.
        parsed.tags = self.tags.clone();
        parsed.tidy_names();
        for ((row, original), input) in parsed
            .ingredients
            .iter_mut()
            .zip(&self.ingredients)
            .zip(amount_inputs)
        {
            if input.is_none() {
                row.amount = original.amount.clone();
            }
        }
        for row in &mut parsed.ingredients {
            row.recover_stashed_range();
            if row.unit.is_empty() && row.amount.bounds().is_some() {
                if let Some((unit, name)) = super::units::leading_unit(&row.name) {
                    row.unit = unit;
                    row.name = name;
                }
            }
        }
        super::duration::normalize(&mut parsed);
        parsed.validate()?;
        Ok(parsed)
    }
    pub fn tidy_names(&mut self) {
        let tidy = |s: &str| s.split_whitespace().collect::<Vec<_>>().join(" ");
        for row in &mut self.ingredients {
            row.name = tidy(&row.name);
        }
        let mut seen = HashSet::new();
        self.tags = self
            .tags
            .iter()
            .map(|s| tidy(s))
            .filter(|s| !s.is_empty() && seen.insert(s.clone()))
            .collect();
    }
    pub fn lowercase_tags(&mut self) {
        let mut seen = HashSet::new();
        self.tags = self
            .tags
            .iter()
            .map(|tag| tag.trim().to_lowercase())
            .filter(|tag| !tag.is_empty() && seen.insert(tag.clone()))
            .collect();
    }
    pub fn validate(&self) -> Result<()> {
        self.validate_fields()?;
        if !self.source.is_empty() && !safe_source(&self.source) {
            return Err(error("Use an http:// or https:// source link."));
        }
        for ingredient in &self.ingredients {
            ingredient.validate()?;
        }
        Ok(())
    }
}
impl WrittenRecipe {
    pub fn parse(&self) -> Result<RecipeContent> {
        // Bound raw input before trimming, dropping blanks or deduplicating.
        self.validate_fields()?;
        let mut seen = HashSet::new();
        let result = RecipeContent {
            title: self.title.trim().into(),
            description: self.description.trim().into(),
            servings: self.servings.trim().into(),
            prep_time: self.prep_time.trim().into(),
            cook_time: self.cook_time.trim().into(),
            total_time: self.total_time.trim().into(),
            source: self.source.trim().into(),
            notes: self.notes.trim().into(),
            tags: self
                .tags
                .iter()
                .map(|s| s.trim().to_lowercase())
                .filter(|s| !s.is_empty() && seen.insert(s.clone()))
                .collect(),
            ingredients: self
                .ingredients
                .iter()
                .map(WrittenIngredient::parse)
                .collect::<Result<_>>()?,
            steps: self
                .steps
                .iter()
                .map(|s| s.trim().to_string())
                .filter(|s| !s.is_empty())
                .collect(),
        };
        result.validate()?;
        Ok(result)
    }
}
impl Recipe {
    pub fn new(content: RecipeContent, now: &str) -> Result<Self> {
        let result = Self {
            schema_version: 2,
            id: RecipeId(uuid::Uuid::new_v4().to_string()),
            favorite: false,
            created_at: now.into(),
            updated_at: now.into(),
            revision: 1,
            content,
        };
        result.validate()?;
        Ok(result)
    }
    pub fn validate(&self) -> Result<()> {
        if !matches!(self.schema_version, 1 | 2) {
            return Err(error("Unsupported recipe schema."));
        }
        if self.schema_version == 1
            && self
                .content
                .ingredients
                .iter()
                .any(|i| matches!(i.amount, Amount::Range { .. }))
        {
            return Err(error("Ranges require recipe schema 2."));
        }
        field(&self.id.0, 100)?;
        if self.id.0.trim().is_empty()
            || !self
                .id
                .0
                .bytes()
                .all(|c| c.is_ascii_alphanumeric() || c == b'_' || c == b'-')
            || self.revision == 0
            || self.revision > super::amount::MAX_INTEGER
        {
            return Err(error("Invalid recipe identity or revision."));
        }
        for date in [&self.created_at, &self.updated_at] {
            field(date, 100)?;
            if chrono::DateTime::parse_from_rfc3339(date).is_err() {
                return Err(error("Invalid recipe timestamp."));
            }
        }
        self.content.validate()
    }
    /// Canonical load/sync/ZIP/recovery boundary. No text parsing or snapping.
    pub fn from_json(bytes: &[u8]) -> Result<Self> {
        if bytes.len() > MAX_COLLECTION_BYTES {
            return Err(error("Recipe exceeds its byte limit."));
        }
        // Serde's flattened content cannot enforce the outer object's unknown
        // fields. Check them explicitly at the canonical JSON boundary.
        let raw: serde_json::Value =
            serde_json::from_slice(bytes).map_err(|_| error("Malformed canonical recipe."))?;
        let fields = raw
            .as_object()
            .ok_or_else(|| error("Malformed canonical recipe."))?;
        if fields.keys().any(|key| {
            !matches!(
                key.as_str(),
                "schemaVersion"
                    | "id"
                    | "favorite"
                    | "createdAt"
                    | "updatedAt"
                    | "revision"
                    | "title"
                    | "description"
                    | "servings"
                    | "prepTime"
                    | "cookTime"
                    | "totalTime"
                    | "source"
                    | "tags"
                    | "notes"
                    | "ingredients"
                    | "steps"
            )
        }) {
            return Err(error("Unexpected recipe field."));
        }
        let mut value: Self =
            serde_json::from_slice(bytes).map_err(|_| error("Malformed canonical recipe."))?;
        value.validate()?;
        // Schema 1 is an exact subset. Migrate the typed view, never immutable
        // sync history bytes/digests, IDs, revisions, or user text on load.
        value.schema_version = 2;
        Ok(value)
    }
    pub fn to_json(&self) -> Result<Vec<u8>> {
        self.validate()?;
        let bytes = serde_json::to_vec(self).map_err(|_| error("Invalid recipe."))?;
        if bytes.len() > MAX_COLLECTION_BYTES {
            return Err(error("Recipe exceeds its byte limit."));
        }
        Ok(bytes)
    }
}

/// Validates only the written-quantity response shape; provider calls/schema
/// transforms and retry policy belong to C3/C7.
pub fn parse_ai_written(json: &str, now: &str) -> Result<Recipe> {
    bounded(json, MAX_INPUT_BYTES)?;
    let raw: WrittenRecipe =
        serde_json::from_str(json).map_err(|_| error("Malformed written-quantity recipe."))?;
    Recipe::new(raw.parse()?, now)
}
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct IngredientGroup {
    pub name: String,
    pub indices: Vec<usize>,
}
pub fn ingredient_groups(rows: &[Ingredient]) -> Vec<IngredientGroup> {
    let mut groups: Vec<IngredientGroup> = Vec::new();
    let mut positions = HashMap::new();
    for (index, row) in rows.iter().enumerate() {
        let key = normalize_name(&row.section);
        let position = *positions.entry(key).or_insert_with(|| {
            groups.push(IngredientGroup {
                name: row.section.clone(),
                indices: Vec::new(),
            });
            groups.len() - 1
        });
        groups[position].indices.push(index);
    }
    groups
}
