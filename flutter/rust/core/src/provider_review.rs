//! Conservative, source-based review labels. No recipe data or formats change.
use super::AiReview;
use crate::recipe::{Recipe, duration, rx, web};
use serde_json::Value;

fn whitespace(text: &str) -> String {
    text.split_whitespace().collect::<Vec<_>>().join(" ")
}

// Only typographic and unit-abbreviation equivalence is accepted for directions.
// In particular, numbers, negation, ingredient names and word order are retained.
fn step_text(text: &str) -> String {
    let mut text = web::decode_entities(text)
        .replace(['‘', '’'], "'")
        .replace(['“', '”'], "\"")
        .replace(['–', '−'], "-");
    // Unicode fraction glyphs and their written fractions are typographic forms
    // of the same number; decimals and different fractions are not substituted.
    text = rx(r"([0-9])([¼½¾⅐⅑⅒⅓⅔⅕⅖⅗⅘⅙⅚⅛⅜⅝⅞])")
        .replace_all(&text, "$1 $2")
        .into_owned();
    for (glyph, fraction) in [
        ('¼', "1/4"),
        ('½', "1/2"),
        ('¾', "3/4"),
        ('⅐', "1/7"),
        ('⅑', "1/9"),
        ('⅒', "1/10"),
        ('⅓', "1/3"),
        ('⅔', "2/3"),
        ('⅕', "1/5"),
        ('⅖', "2/5"),
        ('⅗', "3/5"),
        ('⅘', "4/5"),
        ('⅙', "1/6"),
        ('⅚', "5/6"),
        ('⅛', "1/8"),
        ('⅜', "3/8"),
        ('⅝', "5/8"),
        ('⅞', "7/8"),
    ] {
        text = text.replace(glyph, fraction);
    }
    for (pattern, replacement) in [
        (r"(\b[0-9]+(?:/[0-9]+)?\s+)T\b", "${1}tbsp"),
        (r"(\b[0-9]+(?:/[0-9]+)?\s+)t\b", "${1}tsp"),
        (r"(?i)\b(?:tablespoons?|tbsps?|tbs|tb)\b", "tbsp"),
        (r"(?i)\b(?:teaspoons?|tsps?)\b", "tsp"),
        (r"(?i)\b(?:ounces?|oz)\b", "oz"),
        (r"(?i)\b(?:pounds?|lbs?)\b", "lb"),
        (r"(?i)\b(?:minutes?|mins?)\b", "min"),
        (r"(?i)\b(?:hours?|hrs?)\b", "hr"),
        (r"(?i)\b(?:seconds?|secs?)\b", "sec"),
        (r"(?i)\b(?:cups?|c)\b", "cup"),
        (r"(?i)\b(?:milliliters?|millilitres?|ml)\b", "ml"),
        (r"(?i)\b(?:liters?|litres?|l)\b", "l"),
        (r"(?i)\b(?:kilograms?|kg)\b", "kg"),
        (r"(?i)\b(?:grams?|g)\b", "g"),
    ] {
        text = rx(pattern).replace_all(&text, replacement).into_owned();
    }
    text = rx(r"\b(tbsp|tsp|oz|lb|cup|ml|l|kg|g|min|hr|sec)\.\s+([a-z0-9])")
        .replace_all(&text, "$1 $2")
        .into_owned();
    whitespace(&text)
}

fn embedded_html(source: &str) -> Option<String> {
    let (data, _) = source
        .strip_prefix("Downloaded embedded data:\n")?
        .split_once("\nDownloaded page text:\n")?;
    fn categories(value: &mut Value, depth: usize) {
        if depth > 32 {
            return;
        }
        match value {
            Value::Array(items) => {
                for v in items {
                    categories(v, depth + 1);
                }
            }
            Value::Object(object) => {
                let is_recipe = object.get("@type").is_some_and(|t| {
                    t == "Recipe"
                        || t.as_array()
                            .is_some_and(|a| a.iter().any(|v| v == "Recipe"))
                });
                if is_recipe {
                    let mut tags = Vec::new();
                    for key in ["keywords", "recipeCategory"] {
                        if let Some(v) = object.get(key) {
                            match v {
                                Value::String(s) => tags
                                    .extend(s.split(',').map(|s| Value::String(s.trim().into()))),
                                Value::Array(a) => {
                                    tags.extend(a.iter().filter(|v| v.is_string()).cloned())
                                }
                                _ => {}
                            }
                        }
                    }
                    object.insert("keywords".into(), Value::Array(tags));
                }
                for v in object.values_mut() {
                    categories(v, depth + 1);
                }
            }
            _ => {}
        }
    }
    let mut html = String::new();
    for value in serde_json::Deserializer::from_str(data)
        .into_iter::<Value>()
        .take(32)
    {
        let mut value = value.ok()?;
        categories(&mut value, 0);
        html.push_str(&format!(
            "<script type=\"application/ld+json\">{value}</script>"
        ));
    }
    Some(html)
}

fn copied_sentence(source: &str, lines: &[String], value: &str) -> bool {
    if value.is_empty() {
        return false;
    }
    let matches = |text: &str| {
        text.match_indices(value).any(|(start, _)| {
            let before = text[..start].trim_end();
            let after = text[start + value.len()..].trim_start();
            (before.is_empty() || before.ends_with(['.', '!', '?']))
                && (after.is_empty()
                    || after.starts_with(['.', '!', '?'])
                    || value.ends_with(['.', '!', '?']))
        })
    };
    // Permit source sentence splitting without accepting suffixes that drop words.
    matches(source) || lines.iter().any(|line| matches(line))
}

fn field_value(field: &str, value: &str) -> String {
    let value = whitespace(value).to_lowercase().replace(['–', '−'], "-");
    if field == "servings" {
        let value = rx(r"(?i)^(?:makes?|serves?|yield|servings?)\s*:?\s*").replace(&value, "");
        rx(r"(?i)\s+(?:servings?|people|persons?)\.?$")
            .replace(&value, "")
            .trim()
            .to_string()
    } else if field == "tags" {
        value
    } else {
        duration::readable(&value)
    }
}

fn label_pattern(field: &str) -> &'static str {
    match field {
        "servings" => r"(?i)^(?:servings?|serves?|feeds?|makes?|yield)\s*:?\s*(.*)$",
        "prepTime" => r"(?i)^(?:prep(?:aration)?\s*(?:time)?)\s*:?\s*(.*)$",
        "cookTime" => r"(?i)^(?:cook(?:ing)?\s*(?:time)?)\s*:?\s*(.*)$",
        "totalTime" => r"(?i)^(?:total\s*(?:time)?)\s*:?\s*(.*)$",
        _ => r"(?i)^(?:tags?|keywords?|course|category|categories)\s*:?\s*(.*)$",
    }
}

fn field_in_lines(source: &str, field: &str, value: &str) -> bool {
    let wanted = field_value(field, value);
    let lines: Vec<_> = source
        .lines()
        .map(str::trim)
        .filter(|s| !s.is_empty())
        .collect();
    for (i, line) in lines.iter().enumerate() {
        if let Some(c) = rx(label_pattern(field)).captures(line) {
            let rest = c.get(1).unwrap().as_str().trim();
            let value_line = if rest.is_empty() { i + 1 } else { i };
            let candidate = if rest.is_empty() {
                lines.get(value_line).copied().unwrap_or("")
            } else {
                rest
            };
            // Rendered pages can put the number and duration unit on separate
            // lines. Accept a neighboring unit only under the matching label.
            let joined;
            let candidate = if field.ends_with("Time")
                && rx(r"^\d+(?:\.\d+)?$").is_match(candidate)
                && lines.get(value_line + 1).is_some_and(|line| {
                    rx(r"(?i)^(?:days?|hours?|hrs?|minutes?|mins?|seconds?|secs?)$").is_match(line)
                }) {
                joined = format!("{candidate} {}", lines[value_line + 1]);
                joined.as_str()
            } else {
                candidate
            };
            if field == "tags" {
                if candidate
                    .split([',', ';', '|'])
                    .any(|s| field_value(field, s) == wanted)
                {
                    return true;
                }
            } else if field_value(field, candidate) == wanted {
                return true;
            }
        }
        // Common prose yield forms, with numeric boundaries, not bare numbers.
        if field == "servings" {
            for c in rx(r"(?i)\b(?:serves|feeds|makes)\s+(\d+(?:\s*[-–]\s*\d+)?)\s*(?:people|persons|servings)?\b").captures_iter(line) {
                if field_value(field, &c[1]) == wanted { return true; }
            }
            if let Some(c) = rx(r"(?i)^(\d+(?:\s*[-–]\s*\d+)?)\s+servings?\.?$").captures(line) {
                if field_value(field, &c[1]) == wanted {
                    return true;
                }
            }
        }
    }
    false
}

pub(super) fn from_source(source: &str, recipe: &Recipe) -> AiReview {
    let c = &recipe.content;
    let mut review = AiReview::default();
    // Embedded recipe data is decoded through the existing bounded parser; use
    // only a uniquely selected recipe, never metadata from a neighboring card.
    let embedded = embedded_html(source).and_then(|html| {
        web::inspect_page(&html, "https://source.invalid", "2026-01-01T00:00:00Z").ok()
    });
    let selected = embedded.as_ref().and_then(|page| {
        let candidates: Vec<_> = page
            .imports
            .candidates
            .iter()
            .filter(|r| r.recipe.content.title.eq_ignore_ascii_case(&c.title))
            .collect();
        if candidates.len() == 1 {
            Some(&candidates[0].recipe.content)
        } else if page.imports.candidates.len() == 1 {
            Some(&page.imports.candidates[0].recipe.content)
        } else {
            None
        }
    });
    for (field, value) in [
        ("servings", &c.servings),
        ("prepTime", &c.prep_time),
        ("cookTime", &c.cook_time),
        ("totalTime", &c.total_time),
    ] {
        let from_embedded = selected.is_some_and(|s| {
            let original = match field {
                "servings" => &s.servings,
                "prepTime" => &s.prep_time,
                "cookTime" => &s.cook_time,
                _ => &s.total_time,
            };
            !original.is_empty() && field_value(field, original) == field_value(field, value)
        });
        if !value.is_empty() && !from_embedded && !field_in_lines(source, field, value) {
            review.ai_guessed_fields.push(field.into());
        }
    }
    if c.tags.iter().any(|tag| {
        !selected.is_some_and(|s| s.tags.contains(tag)) && !field_in_lines(source, "tags", tag)
    }) {
        review.ai_guessed_fields.push("tags".into());
    }
    let mut directions = source.to_string();
    if let Some(s) = selected {
        directions.push_str(&format!("\n{}", s.steps.join("\n")));
    }
    let lines: Vec<_> = directions
        .lines()
        .map(|line| {
            let line = rx(r"^\s*(?:[-*•]|[0-9]+[.)])\s+").replace(line, "");
            step_text(&line)
        })
        .collect();
    let directions = step_text(&directions);
    review.ai_guessed_steps = c
        .steps
        .iter()
        .enumerate()
        .filter(|(_, step)| !copied_sentence(&directions, &lines, &step_text(step)))
        .map(|(i, _)| i as u32)
        .collect();
    review.ai_guessed_fields.sort();
    review
}
