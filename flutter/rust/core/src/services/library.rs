//! Exact name edits: quantities, other content and content timestamps are untouched.
use super::*;
use std::collections::BTreeMap;

pub struct LibraryUndo {
    before: Vec<Recipe>,
    after: Vec<Recipe>,
    placements: BTreeMap<String, (Option<String>, Option<String>)>,
}

impl LibraryUndo {
    pub fn count(&self) -> u32 {
        self.before.len() as u32
    }
}

impl Service {
    pub fn add_library_tag(
        &self,
        generation: i64,
        ids: &[RecipeId],
        tag: &str,
        operation: &Operation,
    ) -> Result<(Snapshot, LibraryUndo)> {
        if ids.is_empty()
            || tag.trim().is_empty()
            || ids.iter().collect::<HashSet<_>>().len() != ids.len()
        {
            return Err(Error::Validation);
        }
        let mut undo = LibraryUndo {
            before: vec![],
            after: vec![],
            placements: BTreeMap::new(),
        };
        let snapshot =
            self.mutate_with_reason(generation, operation, "before_library", |book| {
                for id in ids {
                    let before = recipe_from_book(book, id)?;
                    if before.content.tags.iter().any(|name| name == tag) {
                        continue;
                    }
                    let mut recipe = before.clone();
                    recipe.content.tags.push(tag.to_owned());
                    recipe.revision = recipe.revision.checked_add(1).ok_or(Error::Limit)?;
                    recipe.validate()?;
                    undo.before.push(before);
                    undo.after.push(recipe.clone());
                    put_recipe(book, recipe)?;
                }
                if undo.before.is_empty() {
                    return Err(Error::StaleWrite);
                }
                Ok(())
            })?;
        Ok((snapshot, undo))
    }

    pub fn change_library_names(
        &self,
        generation: i64,
        tags: bool,
        sources: &[String],
        target: Option<&str>,
        operation: &Operation,
    ) -> Result<(Snapshot, LibraryUndo)> {
        if sources.is_empty()
            || sources.len() > recipe::MAX_ITEMS
            || sources.iter().any(|s| s.trim().is_empty())
            || sources.iter().collect::<HashSet<_>>().len() != sources.len()
            || target.is_some_and(|s| s.trim().is_empty() || sources.iter().any(|old| old == s))
            || (!tags && target.is_none())
        {
            return Err(Error::Validation);
        }
        let mut undo = LibraryUndo {
            before: vec![],
            after: vec![],
            placements: BTreeMap::new(),
        };
        let snapshot =
            self.mutate_with_reason(generation, operation, "before_library", |book| {
                let mut found = HashSet::new();
                for mut recipe in Self::recipes(book)? {
                    let before = recipe.clone();
                    if tags {
                        let touched = recipe
                            .content
                            .tags
                            .iter()
                            .any(|name| sources.contains(name));
                        let mut names = Vec::new();
                        for name in &recipe.content.tags {
                            if sources.contains(name) {
                                found.insert(name.clone());
                                if let Some(target) = target {
                                    names.push(target.to_owned());
                                }
                            } else {
                                names.push(name.clone());
                            }
                        }
                        // A merge leaves one copy at the first occurrence, retaining tag order.
                        if touched && target.is_some() {
                            let mut seen_target = false;
                            names.retain(|name| {
                                if Some(name.as_str()) != target {
                                    return true;
                                }
                                let keep = !seen_target;
                                seen_target = true;
                                keep
                            });
                        }
                        recipe.content.tags = names;
                    } else {
                        for ingredient in &mut recipe.content.ingredients {
                            if sources.contains(&ingredient.name) {
                                found.insert(ingredient.name.clone());
                                ingredient.name = target.unwrap().to_owned();
                            }
                        }
                    }
                    if recipe != before {
                        recipe.revision = recipe.revision.checked_add(1).ok_or(Error::Limit)?;
                        recipe.validate()?;
                        undo.before.push(before);
                        undo.after.push(recipe.clone());
                        put_recipe(book, recipe)?;
                    }
                }
                if sources.iter().any(|name| !found.contains(name)) || undo.before.is_empty() {
                    return Err(Error::StaleWrite);
                }
                if !tags {
                    let placements = &mut book.shopping_setup.placements;
                    let before = placements.clone();
                    let target_key = crate::shopping_categories::normalize(target.unwrap());
                    // Preserve a deliberate destination aisle when it already exists;
                    // otherwise carry the first source's remembered aisle with the name.
                    for source in sources {
                        let key = crate::shopping_categories::normalize(source);
                        if key != target_key {
                            if let Some(aisle) = placements.get(&key).cloned() {
                                // The old normalized key may also belong to a separate
                                // spelling/plural or an existing local shopping row.
                                placements.entry(target_key.clone()).or_insert(aisle);
                            }
                        }
                    }
                    for key in before.keys().chain(placements.keys()) {
                        if before.get(key) != placements.get(key) {
                            undo.placements.insert(
                                key.clone(),
                                (before.get(key).cloned(), placements.get(key).cloned()),
                            );
                        }
                    }
                }
                Ok(())
            })?;
        Ok((snapshot, undo))
    }

    pub fn undo_library_names(
        &self,
        generation: i64,
        undo: &LibraryUndo,
        operation: &Operation,
    ) -> Result<Snapshot> {
        self.mutate_with_reason(generation, operation, "before_library", |book| {
            for (before, after) in undo.before.iter().zip(&undo.after) {
                if recipe_from_book(book, &after.id)? != *after {
                    return Err(Error::StaleWrite);
                }
                let mut restored = before.clone();
                restored.revision = after.revision.checked_add(1).ok_or(Error::Limit)?;
                restored.validate()?;
                put_recipe(book, restored)?;
            }
            for (key, (before, after)) in &undo.placements {
                if book.shopping_setup.placements.get(key) != after.as_ref() {
                    return Err(Error::StaleWrite);
                }
                match before {
                    Some(value) => {
                        book.shopping_setup
                            .placements
                            .insert(key.clone(), value.clone());
                    }
                    None => {
                        book.shopping_setup.placements.remove(key);
                    }
                }
            }
            Ok(())
        })
    }
}
