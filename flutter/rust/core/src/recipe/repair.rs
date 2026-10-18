//! Tolerant new-import boundary. Canonical storage/editor validation stays strict.
use super::{Amount, Ingredient, MAX_ITEMS, Recipe, RecipeContent, Result, error};
use serde_json::Value;

fn bounded_text(text: &str, max: usize, label: &str, warnings: &mut Vec<String>) -> String {
    let mut units = 0;
    let kept: String = text
        .trim()
        .chars()
        .take_while(|c| {
            units += c.len_utf16();
            units <= max
        })
        .collect();
    if units > max {
        warnings.push(format!(
            "{label} was too long and was shortened. Review it."
        ));
    }
    kept
}
fn field(value: &Value, key: &str, max: usize, label: &str, warnings: &mut Vec<String>) -> String {
    match value.get(key) {
        Some(Value::String(s)) => bounded_text(s, max, label, warnings),
        Some(Value::Number(n)) => {
            warnings.push(format!(
                "{label} was a number; it was kept as text. Review it."
            ));
            bounded_text(&n.to_string(), max, label, warnings)
        }
        None => {
            warnings.push(format!("The reply was missing {label}; it was left blank."));
            String::new()
        }
        _ => {
            warnings.push(format!(
                "{label} had an unsupported value and was left blank."
            ));
            String::new()
        }
    }
}
fn list<'a>(value: &'a Value, key: &str, warnings: &mut Vec<String>) -> &'a [Value] {
    match value.get(key).and_then(Value::as_array) {
        Some(rows) => {
            if rows.len() > MAX_ITEMS {
                warnings.push(format!(
                    "{key} exceeded the item limit; extra entries were dropped."
                ));
            }
            &rows[..rows.len().min(MAX_ITEMS)]
        }
        None => {
            warnings.push(format!(
                "The reply was missing usable {key}; review and add them if needed."
            ));
            &[]
        }
    }
}

pub fn written(value: &Value, now: &str) -> Result<(Recipe, Vec<String>)> {
    let mut warnings = Vec::new();
    let mut content = RecipeContent {
        title: field(value, "title", 160, "title", &mut warnings),
        description: field(value, "description", 2000, "description", &mut warnings),
        servings: field(value, "servings", 80, "servings", &mut warnings),
        prep_time: field(value, "prepTime", 80, "prep time", &mut warnings),
        cook_time: field(value, "cookTime", 80, "cook time", &mut warnings),
        total_time: field(value, "totalTime", 80, "total time", &mut warnings),
        source: field(value, "source", 2000, "source", &mut warnings),
        notes: field(value, "notes", 20000, "notes", &mut warnings),
        ingredients: Vec::new(),
        steps: Vec::new(),
        tags: Vec::new(),
    };
    if !content.source.is_empty() && !super::model::safe_source(&content.source) {
        warnings.push("Source was not an HTTP(S) link and was dropped.".into());
        content.source.clear();
    }
    for (i, tag) in list(value, "tags", &mut warnings).iter().enumerate() {
        if let Some(tag) = tag.as_str() {
            content.tags.push(bounded_text(
                tag,
                300,
                &format!("Tag {}", i + 1),
                &mut warnings,
            ));
        } else {
            warnings.push(format!("Tag {} was not text and was dropped.", i + 1));
        }
    }
    for (i, step) in list(value, "steps", &mut warnings).iter().enumerate() {
        if let Some(step) = step.as_str() {
            let step = bounded_text(step, 30000, &format!("Step {}", i + 1), &mut warnings);
            if !step.is_empty() {
                content.steps.push(step);
            }
        } else {
            warnings.push(format!("Step {} was not text and was dropped.", i + 1));
        }
    }
    for (i, row) in list(value, "ingredients", &mut warnings).iter().enumerate() {
        if !row.is_object() {
            if let Some(name) = row.as_str().filter(|s| !s.trim().is_empty()) {
                content.ingredients.push(Ingredient {
                    name: bounded_text(name, 2000, "Ingredient", &mut warnings),
                    amount: Amount::Unspecified,
                    unit: String::new(),
                    prep_note: String::new(),
                    section: String::new(),
                    optional: false,
                });
                warnings.push(format!(
                    "Ingredient {} was unstructured; its original line was kept as the name.",
                    i + 1
                ));
            } else {
                warnings.push(format!(
                    "Ingredient {} was unusable and was dropped.",
                    i + 1
                ));
            }
            continue;
        }
        let name = field(
            row,
            "name",
            2000,
            &format!("Ingredient {} name", i + 1),
            &mut warnings,
        );
        if name.is_empty() {
            warnings.push(format!("Ingredient {} had no name and was dropped.", i + 1));
            continue;
        }
        let label = format!("Ingredient “{name}”");
        let amount_text = field(
            row,
            "amount",
            2000,
            &format!("{label} amount"),
            &mut warnings,
        );
        let unit_text = field(row, "unit", 2000, &format!("{label} unit"), &mut warnings);
        let mut prep_note = field(
            row,
            "prepNote",
            2000,
            &format!("{label} prep note"),
            &mut warnings,
        );
        let section = field(
            row,
            "section",
            2000,
            &format!("{label} section"),
            &mut warnings,
        );
        let (mut unit, mut name) = super::units::normalize_ingredient(&unit_text, &name);
        // These unambiguous prefix descriptors are preparation, even when a
        // provider overlooks the shared rules. Never apply to stored recipes.
        let mut preparation = Vec::new();
        while let Some(c) =
            super::rx(r"(?i)^(grated|chopped|shredded|softened|melted|warm|diced|crumbled)\s+(.+)$")
                .captures(&name)
        {
            let descriptor = c[1].to_lowercase();
            if !prep_note
                .split(|c: char| !c.is_alphabetic())
                .any(|word| word.eq_ignore_ascii_case(&descriptor))
            {
                preparation.push(descriptor);
            }
            name = c[2].to_string();
        }
        if !preparation.is_empty() {
            if !prep_note.is_empty() {
                preparation.push(prep_note);
            }
            prep_note = bounded_text(
                &preparation.join("; "),
                2000,
                &format!("{label} prep note"),
                &mut warnings,
            );
        }
        if super::rx(r"(?i)^(each|pieces?|items?|count)$").is_match(&unit)
            || (super::rx(r"(?i)^(?:small |medium |large |extra large )?eggs?$").is_match(&name)
                && super::rx(r"(?i)^eggs?$").is_match(&unit))
        {
            unit.clear();
        }
        let name = bounded_text(&name, 2000, &format!("{label} name"), &mut warnings);
        unit = bounded_text(&unit, 2000, &format!("{label} unit"), &mut warnings);
        let amount = match Amount::parse_new(&amount_text) {
            Ok(amount) => amount,
            Err(_) => {
                let original = [amount_text.as_str(), unit_text.as_str()]
                    .into_iter()
                    .filter(|s| !s.is_empty())
                    .collect::<Vec<_>>()
                    .join(" ");
                prep_note = bounded_text(
                    &[original, prep_note]
                        .into_iter()
                        .filter(|s| !s.is_empty())
                        .collect::<Vec<_>>()
                        .join("; "),
                    2000,
                    &format!("{label} prep note"),
                    &mut warnings,
                );
                unit.clear();
                warnings.push(format!("{label}: quantity “{amount_text}” could not be parsed. Amount and unit were left blank; the original quantity is at the start of the prep note."));
                Amount::Unspecified
            }
        };
        let section_optional =
            super::rx(r"(?i)^(?:optional(?:\s|:|$))|\(optional\)$").is_match(section.trim());
        let optional = row
            .get("optional")
            .and_then(Value::as_bool)
            .unwrap_or_else(|| {
                warnings.push(format!(
                    "{label}: invalid or missing Optional flag was inferred from the section title."
                ));
                false
            })
            || section_optional;
        content.ingredients.push(Ingredient {
            amount,
            unit,
            name,
            prep_note,
            section,
            optional,
        });
    }
    if content.title.is_empty() && content.ingredients.is_empty() && content.steps.is_empty() {
        return Err(error(
            "Nothing usable came back: no title, no ingredients and no steps.",
        ));
    }
    if content.title.is_empty() {
        content.title = "Untitled recipe".into();
        warnings.push("No title came back. Enter a title before saving.".into());
    }
    if content.ingredients.is_empty() {
        warnings.push("No ingredients came back. Review and add them if needed.".into());
    }
    if content.steps.is_empty() {
        warnings.push("No steps came back. Review and add them if needed.".into());
    }
    super::duration::normalize(&mut content);
    content.lowercase_tags();
    for (index, tag) in content.tags.iter_mut().enumerate() {
        *tag = bounded_text(
            tag,
            300,
            &format!("Normalized tag {}", index + 1),
            &mut warnings,
        );
    }
    Ok((Recipe::new(content, now)?, warnings))
}
