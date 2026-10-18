//! Offline HTML/JSON-LD discovery only. Fetching and provider routing are C3/C7.
use super::{
    Candidate, ImportCandidates, MAX_CANDIDATES, MAX_INPUT_BYTES, Recipe, RecipeContent, Result,
    bounded, error, paste::parse_ingredients, rx,
};
use serde_json::Value;

pub fn decode_entities(text: &str) -> String {
    rx(r"(?i)&(#x[0-9a-f]+|#[0-9]+|[a-z][0-9a-z]+);")
        .replace_all(text, |c: &regex::Captures<'_>| {
            let entity = c[1].to_lowercase();
            let named = match entity.as_str() {
                "amp" => Some("&"),
                "lt" => Some("<"),
                "gt" => Some(">"),
                "quot" => Some("\""),
                "apos" => Some("'"),
                "nbsp" => Some(" "),
                "frac14" => Some("¼"),
                "frac12" => Some("½"),
                "frac34" => Some("¾"),
                "ndash" => Some("–"),
                "mdash" => Some("—"),
                "rsquo" => Some("’"),
                "lsquo" => Some("‘"),
                "rdquo" => Some("”"),
                "ldquo" => Some("“"),
                "deg" => Some("°"),
                "hellip" => Some("…"),
                "bull" => Some("•"),
                "times" => Some("×"),
                "copy" => Some("©"),
                _ => None,
            };
            if let Some(s) = named {
                return s.to_string();
            }
            let code = if let Some(s) = entity.strip_prefix("#x") {
                u32::from_str_radix(s, 16).ok()
            } else if let Some(s) = entity.strip_prefix('#') {
                s.parse::<u32>().ok()
            } else {
                None
            };
            code.filter(|n| *n > 0)
                .and_then(char::from_u32)
                .map(|c| c.to_string())
                .unwrap_or_else(|| c[0].into())
        })
        .into_owned()
}
pub fn readable_text(html: &str) -> Result<String> {
    bounded(html, MAX_INPUT_BYTES)?;
    let mut text = String::new();
    let mut skip: Vec<String> = Vec::new();
    for token in rx(r#"(?s)<!--.*?(?:-->|$)|<![^>]*>|</?[A-Za-z][^>"']*(?:(?:"[^"]*"|'[^']*')[^>"']*)*>|[^<]+|<"#).find_iter(html) {
        let token=token.as_str();if token.starts_with("<!"){continue;}
        if let Some(c)=rx(r"^<(/)?([a-zA-Z][\w:-]*)\b").captures(token) {
            let name=c[2].to_lowercase();let closing=c.get(1).is_some();
            let skipped=matches!(name.as_str(),"script"|"style"|"nav"|"noscript"|"template");
            if !skip.is_empty(){
                // Script/style contents are raw text: apparent opening tags in
                // JavaScript/CSS strings cannot nest another skipped element.
                let raw = skip.last().is_some_and(|n| matches!(n.as_str(), "script" | "style" | "noscript"));
                if closing&&skip.last()==Some(&name){skip.pop();}
                else if !raw && !closing&&skipped{skip.push(name);}
                continue;
            }
            if !closing&&skipped{skip.push(name);continue;}
            if matches!(name.as_str(),"p"|"div"|"section"|"article"|"main"|"h1"|"h2"|"h3"|"h4"|"h5"|"h6"|"li"|"ul"|"ol"|"br"|"hr"|"tr"|"table"|"blockquote"){text.push('\n');}
        } else if skip.is_empty(){text.push_str(&decode_entities(token));}
    }
    let text = rx(r"[\t\x0c\x0b ]+").replace_all(&text, " ");
    let text = rx(r" *\n *").replace_all(&text, "\n");
    Ok(rx(r"\n{3,}").replace_all(&text, "\n\n").trim().into())
}
/// Preserve embedded source verbatim even when it cannot be parsed locally.
pub fn ai_context(html: &str) -> Result<String> {
    bounded(html, MAX_INPUT_BYTES)?;
    let mut embedded = String::new();
    for captures in
        rx(r#"(?is)<script\b[^>]*type\s*=\s*["']application/ld\+json["'][^>]*>(.*?)</script\s*>"#)
            .captures_iter(html)
    {
        embedded.push_str(&captures[1]);
        embedded.push('\n');
    }
    let context = format!(
        "Downloaded embedded data:\n{embedded}\nDownloaded page text:\n{}",
        readable_text(html)?
    );
    // Headers can take context just over the input cap. Truncate at UTF-8 boundary.
    let mut end = context.len().min(MAX_INPUT_BYTES);
    while !context.is_char_boundary(end) {
        end -= 1;
    }
    Ok(context[..end].into())
}
fn clean(value: &Value) -> String {
    match value {
        Value::String(s) => readable_text(s).unwrap_or_default(),
        Value::Number(n) => n.to_string(),
        _ => String::new(),
    }
}
fn strings(value: &Value) -> Vec<String> {
    match value {
        Value::Array(a) => a.iter().map(clean).filter(|s| !s.is_empty()).collect(),
        _ => {
            let s = clean(value);
            if s.is_empty() { Vec::new() } else { vec![s] }
        }
    }
}
fn has_type(value: &Value, kind: &str) -> bool {
    strings(&value["@type"])
        .iter()
        .any(|s| s == kind || s.ends_with(&format!("/{kind}")) || s.ends_with(&format!("#{kind}")))
}
fn time(value: &Value) -> String {
    super::duration::readable(&clean(value))
}
fn truthy(value: &&Value) -> bool {
    match value {
        Value::Null => false,
        Value::Bool(v) => *v,
        Value::String(s) => !s.is_empty(),
        Value::Number(n) => n.as_f64() != Some(0.0),
        _ => true,
    }
}
fn instructions(value: &Value, depth: usize, steps: &mut Vec<String>) -> Result<()> {
    if depth > 32 || steps.len() > super::MAX_ITEMS {
        return Err(error("Recipe instructions exceed complexity limits."));
    }
    match value {
        Value::Array(a) => {
            for v in a {
                instructions(v, depth + 1, steps)?;
            }
        }
        Value::String(_) => {
            let s = clean(value);
            if !s.is_empty() {
                steps.push(s);
            }
        }
        Value::Object(_) => {
            if has_type(value, "HowToSection") {
                let title = clean(&value["name"]);
                if !title.is_empty() {
                    steps.push(title);
                }
                instructions(
                    value
                        .get("itemListElement")
                        .filter(truthy)
                        .or_else(|| value.get("steps"))
                        .unwrap_or(&Value::Null),
                    depth + 1,
                    steps,
                )?;
            } else if let Some(child) = value
                .get("itemListElement")
                .filter(truthy)
                .or_else(|| value.get("item").filter(truthy))
            {
                instructions(child, depth + 1, steps)?;
            } else {
                let text = clean(&value["text"]);
                let text = if text.is_empty() {
                    clean(&value["name"])
                } else {
                    text
                };
                if !text.is_empty() {
                    steps.push(text);
                }
            }
        }
        _ => {}
    }
    Ok(())
}
pub fn map_json_ld(value: &Value, source: &str, now: &str) -> Result<Candidate> {
    if !value.is_object() {
        return Err(error("Invalid embedded recipe."));
    }
    let ingredient_sources = strings(
        value
            .get("recipeIngredient")
            .filter(|v| !v.is_null())
            .or_else(|| value.get("ingredients"))
            .unwrap_or(&Value::Null),
    );
    let rows = parse_ingredients(&ingredient_sources.join("\n"), "")?;
    let mut warnings = Vec::new();
    let mut review = Vec::new();
    for row in &rows {
        if row.issue.is_some() {
            review.push(row.original.clone());
        }
    }
    let mut notes = clean(&value["notes"]);
    if !review.is_empty() {
        warnings
            .push("Some ingredient lines need review; their original wording is preserved.".into());
        if !notes.is_empty() {
            notes.push_str("\n\n");
        }
        notes.push_str("Ingredient lines to review (original wording):\n");
        notes.push_str(&review.join("\n"));
    }
    let mut steps = Vec::new();
    instructions(&value["recipeInstructions"], 0, &mut steps)?;
    let url = value["url"].as_str().unwrap_or("");
    let mut content = RecipeContent {
        title: clean(&value["name"]),
        description: clean(&value["description"]),
        servings: strings(&value["recipeYield"]).join(", "),
        prep_time: time(&value["prepTime"]),
        cook_time: time(&value["cookTime"]),
        total_time: time(&value["totalTime"]),
        source: if super::model::safe_source(url) {
            url.into()
        } else if super::model::safe_source(source) {
            source.into()
        } else {
            String::new()
        },
        tags: if let Some(s) = value["keywords"].as_str() {
            s.split(',')
                .map(|s| clean(&Value::String(s.into())))
                .filter(|s| !s.is_empty())
                .collect()
        } else {
            strings(&value["keywords"])
        },
        ingredients: rows.into_iter().map(|r| r.ingredient).collect(),
        steps,
        notes,
    };
    let mut missing = Vec::new();
    if content.ingredients.is_empty() {
        missing.push("ingredients");
    }
    if content.steps.is_empty() {
        missing.push("directions");
    }
    if !missing.is_empty() {
        warnings.push(format!(
            "Embedded recipe data for “{}” is missing {}.",
            content.title,
            missing.join(" and ")
        ));
    }
    content.validate()?;
    content.lowercase_tags();
    Ok(Candidate {
        recipe: Recipe::new(content, now)?,
        warnings,
        ingredient_sources,
    })
}
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct InspectedPage {
    pub imports: ImportCandidates,
    pub text: String,
}
fn warn(warnings: &mut Vec<String>, message: &str) {
    if !warnings.iter().any(|s| s == message) {
        warnings.push(message.into());
    }
}
fn visit(
    value: &Value,
    depth: usize,
    visited: &mut usize,
    result: &mut ImportCandidates,
    source: &str,
    now: &str,
) {
    if depth > 32 || *visited >= 20_000 {
        warn(
            &mut result.warnings,
            "Some page data was too complex to inspect.",
        );
        return;
    }
    *visited += 1;
    if has_type(value, "Recipe") {
        if result.candidates.len() >= MAX_CANDIDATES {
            warn(
                &mut result.warnings,
                "This page contains more than 50 recipes. Only the first 50 are shown.",
            );
            return;
        }
        match map_json_ld(value, source, now) {
            Ok(candidate) => {
                for warning in &candidate.warnings {
                    warn(&mut result.warnings, warning);
                }
                result.candidates.push(candidate);
            }
            Err(_) => warn(
                &mut result.warnings,
                "A recipe on this page had incomplete or unsupported fields.",
            ),
        }
    }
    let children: Box<dyn Iterator<Item = &Value>> = match value {
        Value::Array(a) => Box::new(a.iter()),
        Value::Object(o) => Box::new(o.values()),
        _ => return,
    };
    for child in children {
        if *visited >= 20_000 {
            warn(
                &mut result.warnings,
                "Some page data was too complex to inspect.",
            );
            break;
        }
        if child.is_array() || child.is_object() {
            visit(child, depth + 1, visited, result, source, now);
        } else {
            *visited += 1;
        }
    }
}
pub fn inspect_page(html: &str, source: &str, now: &str) -> Result<InspectedPage> {
    let text = readable_text(html)?;
    let mut imports = ImportCandidates::default();
    let mut visited = 0;
    for c in rx(r#"(?is)<script\b([^>"']*(?:(?:"[^"]*"|'[^']*')[^>"']*)*)>(.*?)</script\s*>"#)
        .captures_iter(html)
    {
        let Some(t) = rx(r#"(?i)\btype\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+))"#).captures(&c[1])
        else {
            continue;
        };
        let kind = t
            .get(1)
            .or_else(|| t.get(2))
            .or_else(|| t.get(3))
            .expect("type")
            .as_str();
        if !kind.trim().eq_ignore_ascii_case("application/ld+json") {
            continue;
        }
        if visited >= 20_000 {
            warn(
                &mut imports.warnings,
                "Some page data was too complex to inspect.",
            );
            break;
        }
        match serde_json::from_str::<Value>(c[2].trim().trim_start_matches('\u{feff}')) {
            Ok(value) => visit(&value, 0, &mut visited, &mut imports, source, now),
            Err(_) => warn(
                &mut imports.warnings,
                "Some structured recipe data could not be read.",
            ),
        }
    }
    Ok(InspectedPage { imports, text })
}
