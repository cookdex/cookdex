//! Structural conversions. Only the core validates/normalizes domain values.
use crate::api::*;
use cookdex_core::{recipe as r, services as s, shopping};
use std::sync::Mutex;
impl From<s::Error> for ServiceError {
    fn from(e: s::Error) -> Self {
        Self {
            message: e.to_string(),
            code: match e {
                s::Error::Validation => ErrorCode::Validation,
                s::Error::StaleWrite => ErrorCode::StaleWrite,
                s::Error::ConflictChanged => ErrorCode::ConflictChanged,
                s::Error::InvalidData => ErrorCode::InvalidData,
                s::Error::InvalidZip => ErrorCode::InvalidZip,
                s::Error::Limit => ErrorCode::Limit,
                s::Error::Conflict => ErrorCode::Conflict,
                s::Error::Cancelled => ErrorCode::Cancelled,
                s::Error::NoPrevious => ErrorCode::NoPrevious,
                s::Error::Storage => ErrorCode::Storage,
                s::Error::Closed => ErrorCode::Closed,
                s::Error::Credentials => ErrorCode::Credentials,
                s::Error::Provider => ErrorCode::Provider,
                s::Error::Quota => ErrorCode::Quota,
                s::Error::Transport => ErrorCode::Transport,
                s::Error::UrlRetrieval => ErrorCode::Provider,
            },
        }
    }
}
impl From<r::Amount> for Amount {
    fn from(a: r::Amount) -> Self {
        match a {
            r::Amount::Range { lower, upper } => Self::Range {
                lower_numerator: lower.numerator(),
                lower_denominator: lower.denominator(),
                upper_numerator: upper.numerator(),
                upper_denominator: upper.denominator(),
            },
            r::Amount::Rational { value } => Self::Rational {
                numerator: value.numerator(),
                denominator: value.denominator(),
            },
            r::Amount::ToTaste => Self::ToTaste,
            r::Amount::Unspecified => Self::Unspecified,
        }
    }
}
impl TryFrom<Amount> for r::Amount {
    type Error = ServiceError;
    fn try_from(a: Amount) -> Result<Self, Self::Error> {
        Ok(match a {
            Amount::Range {
                lower_numerator,
                lower_denominator,
                upper_numerator,
                upper_denominator,
            } => {
                if [
                    lower_numerator,
                    lower_denominator,
                    upper_numerator,
                    upper_denominator,
                ]
                .iter()
                .any(|n| *n > r::amount::MAX_INTEGER)
                {
                    return Err(s::Error::Validation.into());
                }
                r::Amount::range(
                    r::Rational::new(lower_numerator as u128, lower_denominator as u128)
                        .map_err(s::Error::from)?,
                    r::Rational::new(upper_numerator as u128, upper_denominator as u128)
                        .map_err(s::Error::from)?,
                )
                .map_err(s::Error::from)?
            }
            Amount::Rational {
                numerator,
                denominator,
            } => {
                if numerator > r::amount::MAX_INTEGER || denominator > r::amount::MAX_INTEGER {
                    return Err(s::Error::Validation.into());
                }
                r::Rational::new(numerator as u128, denominator as u128)
                    .map_err(s::Error::from)?
                    .into()
            }
            Amount::ToTaste => Self::ToTaste,
            Amount::Unspecified => Self::Unspecified,
        })
    }
}
impl From<r::Ingredient> for Ingredient {
    fn from(i: r::Ingredient) -> Self {
        Self {
            amount: i.amount.into(),
            unit: i.unit,
            name: i.name,
            prep_note: i.prep_note,
            optional: i.optional,
            section: i.section,
        }
    }
}
impl TryFrom<Ingredient> for r::Ingredient {
    type Error = ServiceError;
    fn try_from(i: Ingredient) -> Result<Self, Self::Error> {
        let r = Self {
            amount: i.amount.try_into()?,
            unit: i.unit,
            name: i.name,
            prep_note: i.prep_note,
            optional: i.optional,
            section: i.section,
        };
        r.validate().map_err(s::Error::from)?;
        Ok(r)
    }
}
impl From<r::RecipeContent> for RecipeFields {
    fn from(f: r::RecipeContent) -> Self {
        Self {
            title: f.title,
            description: f.description,
            servings: f.servings,
            prep_time: f.prep_time,
            cook_time: f.cook_time,
            total_time: f.total_time,
            source: f.source,
            tags: f.tags,
            notes: f.notes,
            ingredients: f.ingredients.into_iter().map(Into::into).collect(),
            steps: f.steps,
        }
    }
}
impl TryFrom<RecipeFields> for r::RecipeContent {
    type Error = ServiceError;
    fn try_from(f: RecipeFields) -> Result<Self, Self::Error> {
        let r = Self {
            title: f.title,
            description: f.description,
            servings: f.servings,
            prep_time: f.prep_time,
            cook_time: f.cook_time,
            total_time: f.total_time,
            source: f.source,
            tags: f.tags,
            notes: f.notes,
            ingredients: f
                .ingredients
                .into_iter()
                .map(TryInto::try_into)
                .collect::<Result<_, _>>()?,
            steps: f.steps,
        };
        r.validate().map_err(s::Error::from)?;
        Ok(r)
    }
}
impl From<r::Recipe> for Recipe {
    fn from(r: r::Recipe) -> Self {
        Self {
            id: r.id.0,
            fields: r.content.into(),
            favorite: r.favorite,
            created_at: r.created_at,
            updated_at: r.updated_at,
            revision: r.revision,
        }
    }
}
impl TryFrom<Recipe> for r::Recipe {
    type Error = ServiceError;
    fn try_from(r: Recipe) -> Result<Self, Self::Error> {
        let r = Self {
            schema_version: 2,
            id: r::RecipeId(r.id),
            content: r.fields.try_into()?,
            favorite: r.favorite,
            created_at: r.created_at,
            updated_at: r.updated_at,
            revision: r.revision,
        };
        r.validate().map_err(s::Error::from)?;
        Ok(r)
    }
}
impl From<shopping::Item> for ShoppingItem {
    fn from(i: shopping::Item) -> Self {
        let quantity_text = i.quantity_text();
        Self {
            id: i.id,
            name: i.name,
            measures: i
                .measures
                .into_iter()
                .map(|m| Measure {
                    amount: m.amount.into(),
                    unit: m.unit,
                })
                .collect(),
            contributor_scales: i.contributor_scales,
            contributor_ids: i.contributors.into_iter().map(|id| id.0).collect(),
            checked: i.checked,
            quantity_text,
            category_id: i.category_id,
        }
    }
}
impl From<s::Snapshot> for CollectionSnapshot {
    fn from(s: s::Snapshot) -> Self {
        Self {
            generation: s.generation,
            has_previous: s.has_previous,
            set_aside_count: s.set_aside_count,
            shopping: s.shopping.into_iter().map(Into::into).collect(),
            shopping_categories: s
                .shopping_categories
                .into_iter()
                .map(|c| ShoppingCategory {
                    id: c.id,
                    name: c.name,
                })
                .collect(),
            summaries: s
                .summaries
                .into_iter()
                .map(|r| RecipeSummary {
                    id: r.id.0,
                    title: r.title,
                    description: r.description,
                    ingredients: r.ingredients,
                    tags: r.tags,
                    notes: r.notes,
                    favorite: r.favorite,
                    created_at: r.created_at,
                    updated_at: r.updated_at,
                    servings: r.servings,
                    prep_time: r.prep_time,
                    cook_time: r.cook_time,
                    total_time: r.total_time,
                    revision: r.revision,
                })
                .collect(),
            conflicts: s
                .conflicts
                .into_iter()
                .map(|c| Conflict {
                    recipe_id: c.recipe_id.0,
                    versions: c
                        .versions
                        .into_iter()
                        .map(|v| ConflictVersion {
                            id: v.id,
                            recipe: v.recipe.map(Into::into),
                            deleted_at: v.deleted_at,
                        })
                        .collect(),
                })
                .collect(),
        }
    }
}
impl From<s::Change> for ChangeBatch {
    fn from(c: s::Change) -> Self {
        Self {
            generation: c.generation,
            changed: c.changed.into_iter().map(|id| id.0).collect(),
            deleted: c.deleted.into_iter().map(|id| id.0).collect(),
            shopping_changed: c.shopping_changed,
            conflicts_changed: c.conflicts_changed,
        }
    }
}
impl From<s::RestoreReport> for RestoreReport {
    fn from(r: s::RestoreReport) -> Self {
        Self {
            shopping_setup: r.shopping_setup,
            added: r.added,
            updated: r.updated,
            skipped: r.skipped,
            conflicts: r.conflicts.into_iter().map(|id| id.0).collect(),
        }
    }
}
impl From<r::ImportCandidates> for ImportCandidates {
    fn from(c: r::ImportCandidates) -> Self {
        Self {
            candidates: c
                .candidates
                .into_iter()
                .map(|c| Candidate {
                    ai_review: None,
                    recipe: c.recipe.into(),
                    warnings: c.warnings,
                    ingredient_sources: c.ingredient_sources,
                })
                .collect(),
            warnings: c.warnings,
            ordinary: c.ordinary,
        }
    }
}
impl From<s::ShoppingResult> for ShoppingResult {
    fn from(r: s::ShoppingResult) -> Self {
        Self {
            snapshot: r.snapshot.into(),
            undo: ShoppingUndo::from_core(r.undo),
        }
    }
}
impl ShoppingUndo {
    pub(crate) fn from_core(undo: shopping::Undo) -> Self {
        Self {
            inner: std::sync::Arc::new(Mutex::new(Some(undo))),
        }
    }
}
