use super::{
    Amount, Candidate, ImportCandidates, Ingredient, MAX_INPUT_BYTES, MAX_ITEMS, Recipe,
    RecipeContent, Result, WrittenIngredient, WrittenRecipe, bounded, error,
};
pub const HEADER: &str = "Recipe Book Text v1";
const END: &str = "--- End recipe ---";
const INGREDIENTS: &str = "Ingredients (amount | unit | name | prep note | optional):";
fn escape(value: &str) -> String {
    value
        .replace('\\', "\\\\")
        .replace('|', "\\|")
        .replace('\n', "\\n")
        .replace('\r', "\\r")
}
fn split(value: &str) -> Result<Vec<String>> {
    let mut fields = vec![String::new()];
    let mut chars = value.chars().peekable();
    while let Some(c) = chars.next() {
        let field = fields.last_mut().expect("field");
        if c == '\\' {
            field.push(match chars.next() {
                Some('n') => '\n',
                Some('r') => '\r',
                Some('|') => '|',
                Some('\\') => '\\',
                _ => return Err(error("Unknown text escape.")),
            });
        } else if c == ' ' && chars.peek() == Some(&'|') {
            chars.next();
            if chars.next() != Some(' ') {
                return Err(error("Escape a literal pipe."));
            }
            fields.push(String::new());
        } else {
            field.push(c);
        }
    }
    Ok(fields)
}
fn single(value: &str) -> Result<String> {
    let mut fields = split(value)?;
    if fields.len() != 1 {
        return Err(error("Escape a literal pipe."));
    }
    Ok(fields.remove(0))
}
/// Human-share output deliberately excludes IDs, timestamps, revision/favorite.
pub fn export_recipe(recipe: &Recipe) -> Result<String> {
    recipe.validate()?;
    let r = &recipe.content;
    let mut out = vec![HEADER.to_string()];
    for (name, value) in [
        ("Title", &r.title),
        ("Description", &r.description),
        ("Servings", &r.servings),
        ("Prep time", &r.prep_time),
        ("Cook time", &r.cook_time),
        ("Total time", &r.total_time),
        ("Source", &r.source),
    ] {
        out.push(format!("{name}: {}", escape(value)));
    }
    out.push(format!(
        "Tags: {}",
        serde_json::to_string(&r.tags).map_err(|_| error("Invalid tags."))?
    ));
    out.extend([String::new(), INGREDIENTS.into()]);
    let mut section = None;
    for row in &r.ingredients {
        if section != Some(&row.section) {
            out.push(format!("Section: {}", escape(&row.section)));
            section = Some(&row.section);
        }
        out.push(format!(
            "- {}",
            [
                row.amount.text(),
                row.unit.clone(),
                row.name.clone(),
                row.prep_note.clone(),
                if row.optional { "yes" } else { "no" }.into()
            ]
            .iter()
            .map(|s| escape(s))
            .collect::<Vec<_>>()
            .join(" | ")
        ));
    }
    out.extend([String::new(), "Steps:".into()]);
    for (index, step) in r.steps.iter().enumerate() {
        out.push(format!("{}. {}", index + 1, escape(step)));
    }
    out.extend([
        String::new(),
        format!("Notes: {}", escape(&r.notes)),
        END.into(),
    ]);
    Ok(out.join("\n"))
}
pub fn export_cookbook(recipes: &[Recipe]) -> Result<String> {
    if recipes.len() > MAX_ITEMS {
        return Err(error("Too many recipes."));
    }
    let mut text = String::new();
    for recipe in recipes {
        let next = export_recipe(recipe)?;
        if text.len() + next.len() + 2 > MAX_INPUT_BYTES {
            return Err(error("Recipe text exceeds its byte limit."));
        }
        if !text.is_empty() {
            text.push_str("\n\n");
        }
        text.push_str(&next);
    }
    Ok(text)
}
struct Reader<'a> {
    lines: Vec<&'a str>,
    position: usize,
}
impl Reader<'_> {
    fn peek(&self) -> Option<&str> {
        self.lines.get(self.position).copied()
    }
    fn next(&mut self) -> Result<&str> {
        let s = self
            .lines
            .get(self.position)
            .copied()
            .ok_or_else(|| error("Incomplete Text v1 recipe."))?;
        self.position += 1;
        Ok(s)
    }
    fn exact(&mut self, expected: &str) -> Result<()> {
        if self.next()? != expected {
            return Err(error("Invalid Text v1 structure."));
        }
        Ok(())
    }
    fn take(&mut self, prefix: &str) -> Result<String> {
        self.blanks();
        single(
            self.next()?
                .strip_prefix(prefix)
                .ok_or_else(|| error("Missing Text v1 field."))?,
        )
    }
    fn blanks(&mut self) {
        while self.peek() == Some("") {
            self.position += 1;
        }
    }
}
fn import_strict(text: &str, now: &str) -> Result<ImportCandidates> {
    bounded(text, MAX_INPUT_BYTES)?;
    let normalized = text
        .trim_start_matches(|c: char| c.is_whitespace() || c == '\u{feff}')
        .replace("\r\n", "\n");
    let mut reader = Reader {
        lines: normalized.split('\n').collect(),
        position: 0,
    };
    let mut result = ImportCandidates::default();
    loop {
        reader.blanks();
        if reader.peek().is_none() {
            break;
        }
        if result.candidates.len() >= MAX_ITEMS {
            return Err(error("Text contains too many recipes."));
        }
        reader.exact(HEADER)?;
        let mut content = WrittenRecipe {
            title: reader.take("Title: ")?,
            description: reader.take("Description: ")?,
            servings: reader.take("Servings: ")?,
            prep_time: reader.take("Prep time: ")?,
            cook_time: reader.take("Cook time: ")?,
            total_time: reader.take("Total time: ")?,
            source: reader.take("Source: ")?,
            tags: Vec::new(),
            ingredients: Vec::new(),
            steps: Vec::new(),
            notes: String::new(),
        };
        let warnings = Vec::new();
        reader.blanks();
        let raw_tags = reader
            .next()?
            .strip_prefix("Tags: ")
            .ok_or_else(|| error("Missing tags."))?;
        let tags: Vec<String> =
            serde_json::from_str(raw_tags).map_err(|_| error("Invalid tags."))?;
        reader.blanks();
        reader.exact(INGREDIENTS)?;
        let mut section = String::new();
        while reader.peek() != Some("Steps:") {
            let line = reader.next()?;
            if line.is_empty() {
                continue;
            }
            if let Some(value) = line.strip_prefix("Section: ") {
                section = single(value)?;
                continue;
            }
            let fields = split(
                line.strip_prefix("- ")
                    .ok_or_else(|| error("Invalid ingredient row."))?,
            )?;
            if fields.len() != 5 {
                return Err(error("Ingredient needs five columns."));
            }
            if !matches!(fields[4].as_str(), "yes" | "no") {
                return Err(error("Invalid Optional flag."));
            }
            if content.ingredients.len() >= MAX_ITEMS {
                return Err(error("Too many ingredients."));
            }
            content.ingredients.push(WrittenIngredient {
                amount: fields[0].clone(),
                unit: fields[1].clone(),
                name: fields[2].clone(),
                prep_note: fields[3].clone(),
                optional: fields[4] == "yes",
                section: section.clone(),
            });
        }
        reader.exact("Steps:")?;
        reader.blanks();
        while !reader.peek().is_some_and(|s| s.starts_with("Notes: ")) {
            if content.steps.len() >= MAX_ITEMS {
                return Err(error("Too many steps."));
            }
            content
                .steps
                .push(reader.take(&format!("{}. ", content.steps.len() + 1))?);
            reader.blanks();
        }
        content.notes = reader.take("Notes: ")?;
        reader.blanks();
        let ingredients = content
            .ingredients
            .into_iter()
            .map(|row| {
                Ok(Ingredient {
                    amount: Amount::parse_exact(&row.amount)?,
                    unit: row.unit,
                    name: row.name,
                    prep_note: row.prep_note,
                    optional: row.optional,
                    section: row.section,
                })
            })
            .collect::<Result<Vec<_>>>()?;
        let mut recipe = Recipe::new(
            RecipeContent {
                title: content.title,
                description: content.description,
                servings: content.servings,
                prep_time: content.prep_time,
                cook_time: content.cook_time,
                total_time: content.total_time,
                source: content.source,
                tags,
                ingredients,
                steps: content.steps,
                notes: content.notes,
            },
            now,
        )?;
        if reader.peek() == Some("Metadata:") {
            reader.next()?;
            recipe.created_at = reader.take("Created: ")?;
            recipe.updated_at = reader.take("Updated: ")?;
            let revision = reader.take("Revision: ")?;
            if !super::rx(r"^[1-9][0-9]*$").is_match(&revision) {
                return Err(error("Invalid revision."));
            }
            recipe.revision = revision.parse().map_err(|_| error("Invalid revision."))?;
            recipe.favorite = match reader.take("Favorite: ")?.as_str() {
                "yes" => true,
                "no" => false,
                _ => return Err(error("Invalid favorite.")),
            };
            reader.blanks();
        }
        reader.exact(END)?;
        recipe.validate()?;
        result.candidates.push(Candidate {
            recipe,
            warnings,
            ingredient_sources: Vec::new(),
        });
    }
    if result.candidates.is_empty() {
        return Err(error("Paste a recipe first."));
    }
    Ok(result)
}

/// Try the unchanged writer's exact grammar first, then undo transport
/// whitespace and word wrapping. Missing fields/end markers stay errors.
pub fn import_text(text: &str, now: &str) -> Result<ImportCandidates> {
    bounded(text, MAX_INPUT_BYTES)?;
    match import_strict(text, now) {
        Ok(parsed) => Ok(parsed),
        Err(original) => import_strict(&unfold_transport(text), now).map_err(|_| original),
    }
}
fn unfold_transport(text: &str) -> String {
    let normalized = text.replace("\r\n", "\n");
    let mut lines: Vec<String> = Vec::new();
    for raw in normalized
        .trim_start_matches(|c: char| c.is_whitespace() || c == '\u{feff}')
        .lines()
    {
        let line = raw.trim();
        if line.is_empty() {
            continue;
        }
        let structural = line == HEADER
            || line == END
            || line == "Steps:"
            || line == "Metadata:"
            || line.starts_with("Ingredients (")
            || line.starts_with("- ")
            || super::rx(r"^[0-9]+\.").is_match(line)
            || [
                "Title:",
                "Description:",
                "Servings:",
                "Prep time:",
                "Cook time:",
                "Total time:",
                "Source:",
                "Tags:",
                "Section:",
                "Notes:",
                "Created:",
                "Updated:",
                "Revision:",
                "Favorite:",
            ]
            .iter()
            .any(|prefix| line.starts_with(prefix));
        if structural || lines.is_empty() {
            let mut value = line.to_string();
            if (value.ends_with(':')
                && value != "Steps:"
                && value != "Metadata:"
                && !value.starts_with("Ingredients ("))
                || super::rx(r"^[0-9]+\.$").is_match(&value)
            {
                value.push(' ');
            }
            lines.push(value);
        } else if let Some(previous) = lines.last_mut() {
            previous.push(' ');
            previous.push_str(line);
        }
    }
    lines.join("\n")
}
