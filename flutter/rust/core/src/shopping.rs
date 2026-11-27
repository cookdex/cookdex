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
pub struct Contribution {
    pub recipe_id: RecipeId,
    pub measure: Measure,
    pub scale: String,
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
    /// Absent on pre-1.10.5 and hand-typed rows. Never infer old shares.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub contributions: Option<Vec<Contribution>>,
    #[serde(default, skip_serializing_if = "std::ops::Not::not")]
    pub edited: bool,
    #[serde(default, skip_serializing_if = "std::ops::Not::not")]
    pub combined: bool,
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
            contributions: None,
            edited: false,
            combined: false,
        };
        validate(std::slice::from_ref(&item))?;
        Ok(item)
    }
    pub fn quantity_text(&self) -> String {
        self.measures
            .iter()
            .map(|m| {
                if self.combined {
                    if let Ok(text) = combined_quantity(m) {
                        return text;
                    }
                } else if self
                    .contributor_scales
                    .iter()
                    .any(|s| !s.is_empty() && s != "×1")
                {
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
        if let Some(shares) = &item.contributions {
            if shares.is_empty() || shares.len() > 10_000 {
                return Err(Error::InvalidData);
            }
            for share in shares {
                if share.recipe_id.0.is_empty()
                    || share.recipe_id.0.len() > 100
                    || share.scale.len() > 100
                    || share.measure.unit.encode_utf16().count() > 2000
                {
                    return Err(Error::InvalidData);
                }
                share.measure.amount.validate()?;
            }
            if !item.edited {
                let rebuilt = measures_for(shares)?;
                if rebuilt != item.measures
                    || shares
                        .iter()
                        .any(|s| !item.contributors.contains(&s.recipe_id))
                    || item
                        .contributors
                        .iter()
                        .any(|id| !shares.iter().any(|s| &s.recipe_id == id))
                {
                    return Err(Error::InvalidData);
                }
            }
        }
    }
    Ok(())
}
fn unit(unit: &str) -> (String, Rational) {
    if let Some(key) = crate::recipe::units::package_key(unit) {
        return (format!("literal:{key}"), Rational::new(1, 1).unwrap());
    }
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

fn merge_weights(measures: &mut Vec<Measure>, incoming: &Measure) -> Result<bool> {
    let (family, from) = unit(&incoming.unit);
    if family != "mass" {
        return Ok(false);
    }
    let indices: Vec<_> = measures
        .iter()
        .enumerate()
        .filter(|(_, m)| unit(&m.unit).0 == "mass" && m.amount.bounds().is_some())
        .map(|(i, _)| i)
        .collect();
    let Some(&first) = indices.first() else {
        return Ok(false);
    };
    let mut target = from;
    let mut target_unit = incoming.unit.clone();
    for &i in &indices {
        let candidate = unit(&measures[i].unit).1;
        if candidate.numerator() as u128 * target.denominator() as u128
            > target.numerator() as u128 * candidate.denominator() as u128
        {
            target = candidate;
            target_unit = crate::recipe::units::normalize(&measures[i].unit);
        }
    }
    let (low, high) = incoming.amount.bounds().expect("numeric incoming weight");
    let (mut low, mut high) = (low.convert(from, target)?, high.convert(from, target)?);
    for &i in &indices {
        let (a, b) = measures[i]
            .amount
            .bounds()
            .expect("numeric existing weight");
        let from = unit(&measures[i].unit).1;
        low = low.checked_add(a.convert(from, target)?)?;
        high = high.checked_add(b.convert(from, target)?)?;
    }
    measures[first] = Measure {
        amount: Amount::range(low, high)?,
        unit: target_unit,
    };
    let removed: HashSet<_> = indices.into_iter().skip(1).collect();
    let mut index = 0;
    measures.retain(|_| {
        let keep = !removed.contains(&index);
        index += 1;
        keep
    });
    Ok(true)
}
fn merge_measure(measures: &mut Vec<Measure>, incoming: &Measure) -> Result<()> {
    let Some((lower, upper)) = incoming.amount.bounds() else {
        measures.push(incoming.clone());
        return Ok(());
    };
    if merge_weights(measures, incoming)? {
        return Ok(());
    }
    let (family, from) = unit(&incoming.unit);
    for measure in measures.iter_mut() {
        let (target_family, to) = unit(&measure.unit);
        if family == target_family {
            if let Some((a, b)) = measure.amount.bounds() {
                measure.amount = Amount::range(
                    a.checked_add(lower.convert(from, to)?)?,
                    b.checked_add(upper.convert(from, to)?)?,
                )?;
                return Ok(());
            }
        }
    }
    measures.push(incoming.clone());
    Ok(())
}
fn measures_for(shares: &[Contribution]) -> Result<Vec<Measure>> {
    let mut measures = vec![];
    for share in shares {
        merge_measure(&mut measures, &share.measure)?;
    }
    Ok(measures)
}

fn measure_text(amount: Amount, unit: &str) -> String {
    [amount.text(), crate::recipe::units::display(unit, amount)]
        .into_iter()
        .filter(|s| !s.is_empty())
        .collect::<Vec<_>>()
        .join(" ")
}
fn decimal(value: Rational) -> String {
    let (n, d) = (value.numerator() as u128, value.denominator() as u128);
    let mut remainder = n % d;
    let mut result = (n / d).to_string();
    if remainder == 0 {
        return result;
    }
    result.push('.');
    // Only use exact short decimals; never round a shopping total.
    for _ in 0..6 {
        remainder *= 10;
        result.push(char::from(b'0' + (remainder / d) as u8));
        remainder %= d;
        if remainder == 0 {
            return result;
        }
    }
    value.text()
}
fn combined_quantity(measure: &Measure) -> Result<String> {
    let key = crate::recipe::units::normalize(&measure.unit);
    let Some((low, high)) = measure.amount.bounds() else {
        return Ok(measure_text(measure.amount, &key));
    };
    if ["g", "kg", "ml", "l"].contains(&key.as_str()) {
        let from = unit(&key).1;
        let base = Rational::new(1, 1)?;
        let low_base = low.convert(from, base)?;
        let high_base = high.convert(from, base)?;
        let large = low_base.numerator() as u128 >= low_base.denominator() as u128 * 1000;
        let target = Rational::new(if large { 1000 } else { 1 }, 1)?;
        let a = decimal(low_base.convert(base, target)?);
        let b = decimal(high_base.convert(base, target)?);
        let label = match (key.as_str(), large) {
            ("g" | "kg", true) => "kg",
            ("g" | "kg", false) => "g",
            (_, true) => "l",
            _ => "ml",
        };
        return Ok(format!(
            "{} {label}",
            if low == high { a } else { format!("{a}–{b}") }
        ));
    }
    if ["cup", "tbsp", "tsp"].contains(&key.as_str()) {
        let from = unit(&key).1;
        let cup = Rational::new(48, 1)?;
        let a = low.convert(from, cup)?;
        let b = high.convert(from, cup)?;
        let familiar = |r: Rational| [1, 2, 3, 4].contains(&r.denominator());
        if familiar(a) && familiar(b) {
            return Ok(measure_text(Amount::range(a, b)?, "cup"));
        }
        if low == high {
            // A half cup plus two tablespoons is clearer than five eighths.
            let whole = a.numerator() / a.denominator();
            for (n, d) in [(3, 4), (2, 3), (1, 2), (1, 3), (1, 4), (0, 1)] {
                let top = whole as u128 * d + n;
                if top == 0 {
                    continue;
                }
                let part = Rational::new(top, d)?;
                let rest_top = a.numerator() as u128 * part.denominator() as u128;
                let part_top = part.numerator() as u128 * a.denominator() as u128;
                if rest_top <= part_top {
                    continue;
                }
                let rest = Rational::new(
                    rest_top - part_top,
                    a.denominator() as u128 * part.denominator() as u128,
                )?;
                let tbsp = rest.convert(cup, Rational::new(3, 1)?)?;
                if tbsp.denominator() == 1 && tbsp.numerator() <= 4 {
                    return Ok(format!(
                        "{} + {}",
                        measure_text(part.into(), "cup"),
                        measure_text(tbsp.into(), "tbsp")
                    ));
                }
                let tsp = rest.convert(cup, Rational::new(1, 1)?)?;
                if [1, 2, 4].contains(&tsp.denominator())
                    && tsp.numerator() <= tsp.denominator() * 2
                {
                    return Ok(format!(
                        "{} + {}",
                        measure_text(part.into(), "cup"),
                        measure_text(tsp.into(), "tsp")
                    ));
                }
            }
        }
        return Ok(crate::recipe::scaling::display_scaled(
            measure.amount,
            &key,
        )?);
    }
    Ok(measure_text(measure.amount, &key))
}
/// Ideas supply a shopping name only. A recipe contributes an actual measure
/// and source. Both choose a row here before the service assigns its aisle.
fn add_row(
    items: &mut Vec<Item>,
    name: &str,
    recipe_row: Option<(&Ingredient, &RecipeId)>,
    scale: &str,
) -> Result<()> {
    let original_unit = recipe_row.map_or("", |(row, _)| row.unit.as_str());
    let contribution = recipe_row.map(|(row, source)| {
        (
            Measure {
                amount: row.amount,
                unit: crate::recipe::units::normalize(&row.unit),
            },
            source,
        )
    });
    let key = normalize_name(name);
    if key.is_empty() || name.encode_utf16().count() > 20_000 {
        return Err(Error::InvalidData);
    }
    let mut matches = items
        .iter()
        .enumerate()
        .filter(|(_, item)| !item.checked && normalize_name(&item.name) == key);
    let matched = match &contribution {
        Some((incoming, _)) if incoming.amount.bounds().is_some() => {
            let package = crate::recipe::units::package_key(original_unit);
            matches.find(|(_, item)| {
                item.measures
                    .first()
                    .is_some_and(|m| m.amount.bounds().is_some())
                    && item
                        .measures
                        .iter()
                        .all(|m| crate::recipe::units::package_key(&m.unit) == package)
            })
        }
        Some(_) => None,
        None => matches.min_by_key(|(_, item)| item.checked),
    }
    .map(|(index, _)| index);
    if let Some(index) = matched {
        let item = &mut items[index];
        let Some((incoming, source)) = contribution else {
            return Ok(());
        };
        merge_measure(&mut item.measures, &incoming)?;
        item.combined = true;
        if let Some(shares) = &mut item.contributions {
            shares.push(Contribution {
                recipe_id: source.clone(),
                measure: incoming,
                scale: scale.into(),
            });
        }
        if !item.contributors.contains(source) {
            item.contributors.push(source.clone());
            if !item.contributor_scales.is_empty() {
                item.contributor_scales.push(String::new());
            }
        }
    } else {
        let (measures, contributors, contributions) = match contribution {
            Some((measure, source)) => (
                vec![measure.clone()],
                vec![source.clone()],
                Some(vec![Contribution {
                    recipe_id: source.clone(),
                    measure,
                    scale: scale.into(),
                }]),
            ),
            None => (Vec::new(), Vec::new(), None),
        };
        items.push(Item {
            id: uuid::Uuid::new_v4().to_string(),
            name: name.into(),
            measures,
            contributors,
            contributor_scales: vec![],
            checked: false,
            category_id: String::new(),
            contributions,
            edited: false,
            combined: false,
        });
    }
    Ok(())
}
/// All-or-nothing even on overflow; selection is explicit (empty means none).
pub fn add(existing: &[Item], recipe: &Recipe, indices: &[u32]) -> Result<Vec<Item>> {
    add_with_scale(existing, recipe, indices, "")
}
fn add_with_scale(
    existing: &[Item],
    recipe: &Recipe,
    indices: &[u32],
    scale: &str,
) -> Result<Vec<Item>> {
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
            add_row(&mut result, &row.name, Some((row, &recipe.id)), scale)?;
        }
    }
    validate(&result)?;
    Ok(result)
}

/// The longest supported batch is a mood-only idea with ten purchases.
pub(crate) fn add_idea_items(items: &mut Vec<Item>, names: &[String]) -> Result<()> {
    if names.is_empty() || names.len() > 10 {
        return Err(Error::InvalidData);
    }
    for name in names {
        add_row(items, name.trim(), None, "")?;
    }
    Ok(())
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
    let suffix = if scale % 2 == 0 {
        format!("×{}", scale / 2)
    } else {
        format!("×{}.5", scale / 2)
    };
    let mut result = add_with_scale(existing, &view, indices, &suffix)?;
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

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RecipeOnList {
    pub recipe_id: RecipeId,
    pub title: String,
    pub item_count: u32,
}
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RemovalLine {
    pub id: String,
    pub name: String,
    pub before: String,
    pub after: Option<String>,
    pub action: String,
    pub reason: String,
}
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RemovalPreview {
    pub generation: i64,
    pub recipe_id: RecipeId,
    pub title: String,
    pub lines: Vec<RemovalLine>,
}
fn references(item: &Item, recipe: &RecipeId) -> bool {
    item.contributors.contains(recipe)
        || item
            .contributions
            .as_ref()
            .is_some_and(|shares| shares.iter().any(|s| &s.recipe_id == recipe))
}
pub fn recipes_on_list(items: &[Item], recipes: &[(RecipeId, String)]) -> Vec<RecipeOnList> {
    let live = recipes.iter().map(|(id, _)| id.clone()).collect();
    let mut result: Vec<_> = recipes
        .iter()
        .filter_map(|(id, title)| {
            let count = items
                .iter()
                .filter(|item| references(item, id) && protection_reason(item, &live).is_none())
                .count();
            (count > 0).then(|| RecipeOnList {
                recipe_id: id.clone(),
                title: title.clone(),
                item_count: count as u32,
            })
        })
        .collect();
    result.sort_by(|a, b| {
        a.title
            .to_lowercase()
            .cmp(&b.title.to_lowercase())
            .then_with(|| a.recipe_id.0.cmp(&b.recipe_id.0))
    });
    result
}
fn protection_reason(item: &Item, live: &HashSet<RecipeId>) -> Option<&'static str> {
    if item.checked {
        Some("Already checked off")
    } else if item.edited {
        Some("Changed by hand")
    } else if item.contributions.is_none() {
        Some(if item.contributors.is_empty() {
            "Added by hand"
        } else {
            "Added before this update"
        })
    } else if item
        .contributions
        .as_ref()
        .unwrap()
        .iter()
        .any(|s| !live.contains(&s.recipe_id))
    {
        Some("A contributing recipe was deleted")
    } else {
        None
    }
}
/// Preview and apply use the same exact reconstruction, never subtraction from
/// rounded display text. Unknown/deleted shares protect the entire line.
pub fn remove_recipe(
    items: &[Item],
    recipe: &RecipeId,
    live: &HashSet<RecipeId>,
) -> Result<(Vec<RemovalLine>, Vec<Item>)> {
    validate(items)?;
    if !live.contains(recipe) {
        return Err(Error::StaleWrite);
    }
    let mut lines = vec![];
    let mut after = vec![];
    for item in items {
        if !references(item, recipe) {
            after.push(item.clone());
            continue;
        }
        let before = item.quantity_text();
        if let Some(reason) = protection_reason(item, live) {
            lines.push(RemovalLine {
                id: item.id.clone(),
                name: item.name.clone(),
                before: before.clone(),
                after: Some(before),
                action: "keep".into(),
                reason: reason.into(),
            });
            after.push(item.clone());
            continue;
        }
        let remaining: Vec<_> = item
            .contributions
            .as_ref()
            .unwrap()
            .iter()
            .filter(|s| &s.recipe_id != recipe)
            .cloned()
            .collect();
        if remaining.is_empty() {
            lines.push(RemovalLine {
                id: item.id.clone(),
                name: item.name.clone(),
                before,
                after: None,
                action: "remove".into(),
                reason: String::new(),
            });
            continue;
        }
        let mut updated = item.clone();
        updated.measures = measures_for(&remaining)?;
        updated.contributors.clear();
        updated.contributor_scales.clear();
        for share in &remaining {
            let index = if let Some(i) = updated
                .contributors
                .iter()
                .position(|id| id == &share.recipe_id)
            {
                i
            } else {
                updated.contributors.push(share.recipe_id.clone());
                updated.contributor_scales.push(String::new());
                updated.contributors.len() - 1
            };
            let label = if share.scale.is_empty() {
                "×1"
            } else {
                &share.scale
            };
            let labels = &mut updated.contributor_scales[index];
            if !labels.split(", ").any(|s| s == label) {
                if !labels.is_empty() {
                    labels.push_str(", ");
                }
                labels.push_str(label);
            }
        }
        updated.combined = remaining.len() > 1;
        updated.contributions = Some(remaining);
        lines.push(RemovalLine {
            id: item.id.clone(),
            name: item.name.clone(),
            before,
            after: Some(updated.quantity_text()),
            action: "reduce".into(),
            reason: String::new(),
        });
        after.push(updated);
    }
    validate(&after)?;
    Ok((lines, after))
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
