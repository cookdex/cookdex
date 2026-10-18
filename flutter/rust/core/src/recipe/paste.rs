use super::{
    Amount, Candidate, ImportCandidates, Ingredient, MAX_INPUT_BYTES, MAX_ITEMS, Recipe,
    RecipeContent, Result, bounded, error, rx,
};

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PastedIngredient {
    pub ingredient: Ingredient,
    pub original: String,
    pub issue: Option<String>,
}
/// Discover explicit ordinary-text recipe boundaries without interpreting amounts.
/// Each block must contain ingredients and directions, so section headings and
/// decorative dividers inside one recipe do not manufacture extra candidates.
pub fn split_recipe_text(text: &str) -> Result<Vec<String>> {
    bounded(text, MAX_INPUT_BYTES)?;
    if text
        .trim_start_matches('\u{feff}')
        .trim_start()
        .starts_with(super::text::HEADER)
    {
        return Ok(vec![text.to_string()]);
    }
    let normalized = text.replace("\r\n", "\n").replace('\r', "\n");
    for pattern in [
        r"(?m)^\s*(?:---+|===+)\s*$",
        r"(?m)^# [^\n]+$",
        r"(?im)^Recipe\s*(?:[0-9]+)?\s*:\s*[^\n]+$",
        r"(?im)^Title[ \t]*:[ \t]*[^\n]+$",
    ] {
        let boundaries: Vec<_> = rx(pattern).find_iter(&normalized).collect();
        if boundaries.is_empty() {
            continue;
        }
        let divider = pattern.contains("---+");
        let mut ranges = Vec::new();
        let mut start = 0;
        for boundary in boundaries.iter().skip(if divider { 0 } else { 1 }) {
            ranges.push(start..boundary.start());
            start = if divider {
                boundary.end()
            } else {
                boundary.start()
            };
        }
        ranges.push(start..normalized.len());
        let blocks: Vec<String> = ranges
            .into_iter()
            .map(|range| normalized[range].trim().to_string())
            .filter(|s| !s.is_empty())
            .collect();
        if blocks.len() < 2 {
            continue;
        }
        if blocks.iter().all(|block| {
            rx(r"(?im)^\s*(?:#{1,6}\s*)?ingredients\s*:?[ \t]*$").is_match(block)
                && rx(
                    r"(?im)^\s*(?:#{1,6}\s*)?(?:steps|directions|instructions|method)\s*:?[ \t]*$",
                )
                .is_match(block)
        }) {
            if blocks.len() > super::MAX_CANDIDATES {
                return Err(error("Too many recipe candidates (maximum 50)."));
            }
            return Ok(blocks);
        }
    }
    Ok(vec![text.to_string()])
}
pub fn parse_ingredients(text: &str, initial_section: &str) -> Result<Vec<PastedIngredient>> {
    bounded(text, MAX_INPUT_BYTES)?;
    super::model::field(initial_section, 2000)?;
    let mut section = initial_section.to_string();
    let mut rows = Vec::new();
    for raw in text.lines() {
        let original = raw.trim();
        let mut line = rx(r"^[•*\-]\s+").replace(original, "").into_owned();
        if line.is_empty() {
            continue;
        }
        if line.ends_with(':') || rx(r"^#{1,6}\s").is_match(&line) {
            section = rx(r"^#{1,6}\s+")
                .replace(&line, "")
                .trim_end_matches(':')
                .trim()
                .into();
            super::model::field(&section, 2000)?;
            continue;
        }
        if rows.len() >= MAX_ITEMS {
            return Err(error("Too many ingredient lines."));
        }
        super::model::field(original, 2000)?;
        let mut amount = Amount::Unspecified;
        let mut unit = String::new();
        let mut issue = None;
        // No lookahead in Rust regex: check token boundary explicitly.
        static QUANTITY: std::sync::LazyLock<regex::Regex> = std::sync::LazyLock::new(|| {
            regex::Regex::new(&format!(
                r"(?i)^{}(?:\s*(?:–|-|\s+to\s+)\s*{})?",
                super::amount::NUMBER_PATTERN,
                super::amount::NUMBER_PATTERN
            ))
            .unwrap()
        });
        let matched = QUANTITY.find(&line).filter(|m| {
            line[m.end()..].chars().next().is_none_or(|c| {
                c.is_whitespace() || (c.is_ascii_alphabetic() && c != 'x' && c != 'X')
            })
        });
        if let Some(m) = matched {
            match Amount::parse_new(m.as_str()) {
                Ok(a) => amount = a,
                Err(_) => {
                    issue = Some("Check the amount, package size, or ingredient name.".into())
                }
            }
            line = line[m.end()..].trim_start().into();
            if rx(r"(?i)^e[+-]?[0-9]").is_match(&line) {
                issue = Some("Check the amount, package size, or ingredient name.".into());
            }
            if let Some(m)=rx(r"(?i)^(?:tsp|teaspoons?|tbsp|tbs|tb|t|tablespoons?|cups?|c|g|grams?|kg|kilograms?|oz|ounces?|lb|lbs|pounds?|ml|millilit(?:er|re)s?|l|lit(?:er|re)s?|cloves?|cans?|pinch(?:es)?|pieces?|slices?|bunch(?:es)?)(?:\.)?(?:\s+|$)").find(&line) {
                unit=super::units::normalize(m.as_str());line=line[m.end()..].into();
            }
        }
        if rx(r"(?i)\bto taste\b").is_match(&line) {
            if amount == Amount::Unspecified {
                amount = Amount::ToTaste;
            }
            line = rx(r"(?i),?\s*to taste\b").replace(&line, "").trim().into();
        }
        let (name, prep) = line
            .split_once(',')
            .map_or((line.as_str(), ""), |(a, b)| (a.trim(), b.trim()));
        if amount == Amount::Unspecified && issue.is_none() {
            issue = Some("No quantity recognized — check this line.".into());
        }
        if name.is_empty() || rx(r"^[\d(\-–]|\([^)]*\d").is_match(name) {
            issue = Some("Check the amount, package size, or ingredient name.".into());
        }
        // Ambiguous lines remain intact, never silently reinterpret packages/ranges.
        let ingredient = if issue.is_some() {
            Ingredient {
                amount: Amount::Unspecified,
                unit: String::new(),
                name: original.into(),
                prep_note: String::new(),
                optional: false,
                section: section.clone(),
            }
        } else {
            Ingredient {
                amount,
                unit,
                name: name.trim().into(),
                prep_note: prep.into(),
                optional: false,
                section: section.clone(),
            }
        };
        ingredient.validate()?;
        rows.push(PastedIngredient {
            ingredient,
            original: original.into(),
            issue,
        });
    }
    Ok(rows)
}
pub fn parse_recipe_input(text: &str, now: &str) -> Result<ImportCandidates> {
    bounded(text, MAX_INPUT_BYTES)?;
    let text = text.trim_start_matches('\u{feff}').trim_start();
    if text.starts_with(super::text::HEADER) {
        return super::text::import_text(text, now);
    }
    if text.trim().is_empty() {
        return Err(error("Paste a recipe first."));
    }
    let mut content = RecipeContent {
        title: String::new(),
        description: String::new(),
        servings: String::new(),
        prep_time: String::new(),
        cook_time: String::new(),
        total_time: String::new(),
        source: String::new(),
        tags: Vec::new(),
        notes: String::new(),
        ingredients: Vec::new(),
        steps: Vec::new(),
    };
    let mut warnings =
        vec!["Review every field before saving. Plain text can be ambiguous.".into()];
    let mut mode = "";
    let mut section = String::new();
    let mut notes = Vec::new();
    let mut extra = Vec::new();
    let mut sources = Vec::new();
    let normalized = text.replace("\r\n", "\n").replace('\r', "\n");
    for raw in normalized.lines() {
        let line = rx(r"^#{1,6}\s+").replace(raw.trim(), "");
        if line.is_empty() {
            continue;
        }
        let heading = line.trim_end_matches(':').to_lowercase();
        if matches!(
            heading.as_str(),
            "ingredients" | "method" | "directions" | "instructions" | "steps" | "notes"
        ) {
            mode = if heading == "ingredients" {
                "ingredients"
            } else if heading == "notes" {
                "notes"
            } else {
                "steps"
            };
            continue;
        }
        if let Some(c)=rx(r"(?i)^(title|servings|serves|yield|prep time|cook time|total time|time|source|tags|notes)\s*:\s*(.*)$").captures(&line) {
            let value=c[2].to_string();match c[1].to_lowercase().as_str(){
                "title"=>content.title=value,"servings"|"serves"|"yield"=>content.servings=value,"prep time"=>content.prep_time=value,"cook time"=>content.cook_time=value,"time"|"total time"=>content.total_time=value,"source"=>content.source=value,
                "tags"=>{for tag in value.split(',').map(str::trim).filter(|s|!s.is_empty()){if !content.tags.iter().any(|s|s==tag){content.tags.push(tag.into());}}},"notes"=>{notes.push(value);mode="notes"},_=>unreachable!() }continue;
        }
        if content.title.is_empty()
            && mode.is_empty()
            && !rx(r"^(?:[0-9¼½¾⅓⅔⅛⅜⅝⅞]|[-•*]\s)").is_match(&line)
        {
            content.title = line.into();
            continue;
        }
        if mode == "notes" {
            notes.push(raw.into());
            continue;
        }
        if mode == "steps" || (mode != "ingredients" && rx(r"^[0-9]+[.)]\s+").is_match(&line)) {
            mode = "steps";
            content
                .steps
                .push(rx(r"^[0-9]+[.)]\s+").replace(&line, "").into());
            continue;
        }
        if mode == "ingredients"
            || rx(r"^(?:[-•*]\s*)?(?:[0-9¼½¾⅓⅔⅛⅜⅝⅞])|(?i:\bto taste\b)").is_match(&line)
        {
            if line.ends_with(':') {
                section = line.trim_end_matches(':').into();
                continue;
            }
            for row in parse_ingredients(&line, &section)? {
                if let Some(issue) = row.issue {
                    warnings.push(format!("{}: {issue}", row.original));
                }
                sources.push(row.original);
                content.ingredients.push(row.ingredient);
            }
            continue;
        }
        extra.push(raw.to_string());
    }
    if content.title.is_empty() {
        content.title = "Untitled recipe".into();
        warnings.push("No title recognized. Enter a title.".into());
    }
    if content.ingredients.is_empty() {
        warnings.push("No ingredients recognized. Add them before saving if needed.".into());
    }
    if content.steps.is_empty() {
        warnings.push("No steps recognized. Add them before saving if needed.".into());
    }
    if !extra.is_empty() {
        warnings.push("Unclassified text was retained in Notes.".into());
        notes.extend(extra);
    }
    if !content.source.is_empty() && !super::model::safe_source(&content.source) {
        notes.push(format!("Source: {}", content.source));
        content.source.clear();
        warnings.push("A non-link source was retained in Notes.".into());
    }
    content.notes = notes.join("\n");
    super::duration::normalize(&mut content);
    content.validate()?;
    content.lowercase_tags();
    let recipe = Recipe::new(content, now)?;
    Ok(ImportCandidates {
        candidates: vec![Candidate {
            recipe,
            warnings: warnings.clone(),
            ingredient_sources: sources,
        }],
        warnings,
        ordinary: true,
    })
}
