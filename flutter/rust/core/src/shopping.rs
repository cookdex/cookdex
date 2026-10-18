//! Fresh, local-only shopping provenance and exact totals.
use crate::recipe::{Amount, Ingredient, Rational, Recipe, RecipeId, model::normalize_name};
use crate::services::{Error, Result};
use serde::{Deserialize, Serialize};
use std::collections::HashSet;

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct Measure {
    pub amount: Amount,
    pub unit: String,
}
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct Item {
    pub id: String,
    pub name: String,
    /// Empty for detached manual text. Such rows never receive recipe totals.
    pub measures: Vec<Measure>,
    pub contributors: Vec<RecipeId>,
    #[serde(default)]
    pub contributor_scales: Vec<String>,
    pub checked: bool,
    #[serde(default)]
    pub category_id: String,
}
impl Item {
    pub fn manual(name: String) -> Result<Self> {
        let item = Self {
            id: uuid::Uuid::new_v4().to_string(),
            name: name.trim().into(),
            measures: vec![],
            contributors: vec![],
            contributor_scales: vec![],
            checked: false,
            category_id: String::new(),
        };
        validate(std::slice::from_ref(&item))?;
        Ok(item)
    }
    pub fn quantity_text(&self) -> String {
        self.measures
            .iter()
            .map(|m| {
                if !self.contributor_scales.is_empty() {
                    if let Ok(text) = crate::recipe::scaling::display_scaled(m.amount, &m.unit) {
                        return text;
                    }
                }
                let parts = [
                    m.amount.text(),
                    crate::recipe::units::display(
                        &crate::recipe::units::normalize(&m.unit),
                        m.amount,
                    ),
                ];
                let text = parts
                    .into_iter()
                    .filter(|s| !s.is_empty())
                    .collect::<Vec<_>>()
                    .join(" ");
                if text.is_empty() && self.measures.len() > 1 {
                    "unspecified quantity".into()
                } else {
                    text
                }
            })
            .collect::<Vec<_>>()
            .join(" + ")
    }
}
pub fn validate(items: &[Item]) -> Result<()> {
    if items.len() > 10_000 {
        return Err(Error::Limit);
    }
    let mut ids = HashSet::new();
    for item in items {
        if item.id.is_empty()
            || item.id.len() > 100
            || !ids.insert(&item.id)
            || item.name.trim().is_empty()
            || item.name.encode_utf16().count() > 20_000
            || item.measures.len() > 10_000
            || item.contributors.len() > 10_000
            || (!item.contributor_scales.is_empty()
                && item.contributor_scales.len() != item.contributors.len())
            || item.contributor_scales.iter().any(|s| s.len() > 100)
        {
            return Err(Error::InvalidData);
        }
        let mut sources = HashSet::new();
        if item
            .contributors
            .iter()
            .any(|id| id.0.is_empty() || id.0.len() > 100 || !sources.insert(id))
            || (item.measures.is_empty() && !item.contributors.is_empty())
        {
            return Err(Error::InvalidData);
        }
        for m in &item.measures {
            m.amount.validate()?;
            if m.unit.encode_utf16().count() > 2000 {
                return Err(Error::Limit);
            }
        }
    }
    Ok(())
}
fn unit(unit: &str) -> (String, Rational) {
    let key = crate::recipe::units::normalize(unit);
    let (family, n, d) = match key.as_str() {
        "tsp" | "teaspoon" | "teaspoons" => ("us", 1, 1),
        "tbsp" | "tablespoon" | "tablespoons" => ("us", 3, 1),
        "cup" | "cups" => ("us", 48, 1),
        "ml" | "milliliter" | "milliliters" | "millilitre" | "millilitres" => ("metric", 1, 1),
        "l" | "liter" | "liters" | "litre" | "litres" => ("metric", 1000, 1),
        "g" | "gram" | "grams" => ("mass", 1, 1),
        "kg" | "kilogram" | "kilograms" => ("mass", 1000, 1),
        "oz" | "ounce" | "ounces" => ("mass", 226796185, 8000000),
        "lb" | "lbs" | "pound" | "pounds" => ("mass", 45359237, 100000),
        _ => return (format!("literal:{key}"), Rational::new(1, 1).unwrap()),
    };
    (family.into(), Rational::new(n, d).unwrap())
}
fn add_row(items: &mut Vec<Item>, row: &Ingredient, source: &RecipeId) -> Result<()> {
    let incoming = Measure {
        amount: row.amount,
        unit: crate::recipe::units::normalize(&row.unit),
    };
    let match_index = if row.amount.bounds().is_some() {
        items.iter().position(|item| {
            normalize_name(&item.name) == normalize_name(&row.name)
                && item
                    .measures
                    .first()
                    .is_some_and(|m| m.amount.bounds().is_some())
        })
    } else {
        None
    };
    if let Some(index) = match_index {
        let item = &mut items[index];
        let (lower, upper) = row.amount.bounds().expect("numeric amount");
        let (family, from) = unit(&row.unit);
        let mut merged = false;
        for measure in &mut item.measures {
            let (target_family, to) = unit(&measure.unit);
            if let Some((old_lower, old_upper)) = measure.amount.bounds() {
                if family == target_family {
                    let sum_lower = old_lower.checked_add(lower.convert(from, to)?)?;
                    let sum_upper = old_upper.checked_add(upper.convert(from, to)?)?;
                    if normalize_name(&measure.unit) == normalize_name(&row.unit)
                        || ([1, 2, 3, 4, 8].contains(&sum_lower.denominator())
                            && [1, 2, 3, 4, 8].contains(&sum_upper.denominator()))
                    {
                        measure.amount = Amount::range(sum_lower, sum_upper)?;
                        merged = true;
                        break;
                    }
                }
            }
        }
        if !merged {
            item.measures.push(incoming);
        }
        if !item.contributors.contains(source) {
            item.contributors.push(source.clone());
            if !item.contributor_scales.is_empty() {
                item.contributor_scales.push(String::new());
            }
        }
        item.checked = false;
    } else {
        items.push(Item {
            id: uuid::Uuid::new_v4().to_string(),
            name: row.name.clone(),
            measures: vec![incoming],
            contributors: vec![source.clone()],
            contributor_scales: vec![],
            checked: false,
            category_id: String::new(),
        });
    }
    Ok(())
}
/// All-or-nothing even on overflow; selection is explicit (empty means none).
pub fn add(existing: &[Item], recipe: &Recipe, indices: &[u32]) -> Result<Vec<Item>> {
    validate(existing)?;
    recipe.validate()?;
    let mut result = existing.to_vec();
    let mut seen = HashSet::new();
    for &index in indices {
        if !seen.insert(index) {
            return Err(Error::InvalidData);
        }
        let row = recipe
            .content
            .ingredients
            .get(index as usize)
            .ok_or(Error::InvalidData)?;
        if !crate::shopping_categories::recipe_omitted(&row.name) {
            add_row(&mut result, row, &recipe.id)?;
        }
    }
    validate(&result)?;
    Ok(result)
}

/// Scale selected rows in memory, retaining local multiplier provenance.
pub fn add_scaled(
    existing: &[Item],
    recipe: &Recipe,
    indices: &[u32],
    scale: u32,
) -> Result<Vec<Item>> {
    let factor = crate::recipe::scaling::factor(scale)?;
    let mut view = recipe.clone();
    for row in &mut view.content.ingredients {
        row.amount = crate::recipe::scaling::amount(row.amount, factor)?;
    }
    let mut result = add(existing, &view, indices)?;
    let suffix = if scale % 2 == 0 {
        format!("×{}", scale / 2)
    } else {
        format!("×{}.5", scale / 2)
    };
    for item in &mut result {
        if existing.iter().any(|old| old == item) {
            continue;
        }
        let Some(index) = item.contributors.iter().position(|id| id == &recipe.id) else {
            continue;
        };
        item.contributor_scales
            .resize(item.contributors.len(), String::new());
        let previous = existing
            .iter()
            .find(|old| old.id == item.id && old.contributors.contains(&recipe.id));
        let labels = &mut item.contributor_scales[index];
        if labels.is_empty() && previous.is_some() {
            *labels = "×1".into();
        }
        if !labels.split(", ").any(|s| s == suffix) {
            if !labels.is_empty() {
                labels.push_str(", ");
            }
            labels.push_str(&suffix);
        }
    }
    validate(&result)?;
    Ok(result)
}

#[derive(Debug, Clone)]
pub struct Undo {
    changes: Vec<(usize, Option<Item>, Option<Item>)>,
}
impl Undo {
    pub fn between(before: &[Item], after: &[Item]) -> Self {
        let mut changes = vec![];
        for (index, item) in before.iter().enumerate() {
            let next = after.iter().find(|i| i.id == item.id);
            if next != Some(item) {
                changes.push((index, Some(item.clone()), next.cloned()));
            }
        }
        for item in after
            .iter()
            .filter(|i| !before.iter().any(|b| b.id == i.id))
        {
            changes.push((before.len(), None, Some(item.clone())));
        }
        Self { changes }
    }
    pub fn apply(&self, current: &[Item]) -> Result<Vec<Item>> {
        // Validate every affected row before applying any inverse. Unrelated edits survive.
        for (_, before, after) in &self.changes {
            let id = &after
                .as_ref()
                .or(before.as_ref())
                .ok_or(Error::InvalidData)?
                .id;
            if current.iter().find(|i| &i.id == id) != after.as_ref() {
                return Err(Error::StaleWrite);
            }
        }
        let mut result = current.to_vec();
        for (index, before, after) in &self.changes {
            let id = &after.as_ref().or(before.as_ref()).unwrap().id;
            if let Some(pos) = result.iter().position(|i| &i.id == id) {
                if let Some(item) = before {
                    result[pos] = item.clone();
                } else {
                    result.remove(pos);
                }
            } else if let Some(item) = before {
                result.insert((*index).min(result.len()), item.clone());
            }
        }
        validate(&result)?;
        Ok(result)
    }
}

#[cfg(test)]
mod display_tests {
    use super::*;
    #[test]
    fn existing_units_are_normalized_for_display_without_changing_exact_data() {
        let mut item = Item::manual("pork ribs".into()).unwrap();
        item.measures = vec![
            Measure {
                amount: Amount::parse_new("1").unwrap(),
                unit: "pounds".into(),
            },
            Measure {
                amount: Amount::parse_new("14").unwrap(),
                unit: "ounces".into(),
            },
            Measure {
                amount: Amount::parse_new("2").unwrap(),
                unit: "Cups".into(),
            },
        ];
        let persisted = serde_json::to_string(&item).unwrap();
        let reopened: Item = serde_json::from_str(&persisted).unwrap();
        assert_eq!(reopened.quantity_text(), "1 lb + 14 oz + 2 cups");
        assert_eq!(serde_json::to_string(&reopened).unwrap(), persisted);
    }
}
