//! Public Dart contract: generated structs/enums, opaque session/operation ownership.
use cookdex_core::{self as core, recipe, services};
use flutter_rust_bridge::frb;
use std::sync::{Arc, Mutex};

#[derive(Clone, Debug, PartialEq)]
pub enum Amount {
    Rational {
        numerator: u64,
        denominator: u64,
    },
    Range {
        lower_numerator: u64,
        lower_denominator: u64,
        upper_numerator: u64,
        upper_denominator: u64,
    },
    ToTaste,
    Unspecified,
}
#[derive(Clone, Debug, PartialEq)]
pub struct Ingredient {
    pub amount: Amount,
    pub unit: String,
    pub name: String,
    pub prep_note: String,
    pub optional: bool,
    pub section: String,
}
#[derive(Clone, Debug, PartialEq)]
pub struct PastedIngredient {
    pub ingredient: Ingredient,
    pub original: String,
    pub issue: Option<String>,
}
#[derive(Clone, Debug, PartialEq)]
pub struct RecipeFields {
    pub title: String,
    pub description: String,
    pub servings: String,
    pub prep_time: String,
    pub cook_time: String,
    pub total_time: String,
    pub source: String,
    pub tags: Vec<String>,
    pub notes: String,
    pub ingredients: Vec<Ingredient>,
    pub steps: Vec<String>,
}
#[derive(Clone, Debug, PartialEq)]
pub struct Recipe {
    pub id: String,
    pub fields: RecipeFields,
    pub favorite: bool,
    pub created_at: String,
    pub updated_at: String,
    pub revision: u64,
}
#[derive(Clone, Debug, PartialEq)]
pub struct RecipeSummary {
    pub id: String,
    pub title: String,
    pub description: String,
    pub ingredients: Vec<String>,
    pub tags: Vec<String>,
    pub notes: String,
    pub favorite: bool,
    pub created_at: String,
    pub updated_at: String,
    pub servings: String,
    pub prep_time: String,
    pub cook_time: String,
    pub total_time: String,
    pub revision: u64,
}
#[derive(Clone, Debug, PartialEq)]
pub struct Measure {
    pub amount: Amount,
    pub unit: String,
}
#[derive(Clone, Debug, PartialEq)]
pub struct ShoppingCategory {
    pub id: String,
    pub name: String,
}
#[derive(Clone, Debug, PartialEq)]
pub struct ShoppingItem {
    pub id: String,
    pub name: String,
    pub measures: Vec<Measure>,
    pub contributor_ids: Vec<String>,
    pub contributor_scales: Vec<String>,
    pub checked: bool,
    pub quantity_text: String,
    pub category_id: String,
}
#[derive(Clone, Debug, PartialEq)]
pub struct ConflictVersion {
    pub id: String,
    pub recipe: Option<Recipe>,
    pub deleted_at: Option<String>,
}
#[derive(Clone, Debug, PartialEq)]
pub struct Conflict {
    pub recipe_id: String,
    pub versions: Vec<ConflictVersion>,
}
#[derive(Clone, Debug, PartialEq)]
pub struct CollectionSnapshot {
    pub generation: i64,
    pub summaries: Vec<RecipeSummary>,
    pub shopping: Vec<ShoppingItem>,
    pub shopping_categories: Vec<ShoppingCategory>,
    pub conflicts: Vec<Conflict>,
    pub has_previous: bool,
    pub set_aside_count: u32,
}
#[derive(Clone, Debug, PartialEq)]
pub struct RecipeBackup {
    pub bytes: Vec<u8>,
    pub omitted: u32,
}
#[derive(Clone, Debug)]
pub struct LocalSnapshotEntry {
    pub id: String,
    pub created_at: String,
    pub recipe_count: u32,
    pub omitted_count: u32,
    pub reason: String,
}
#[derive(Clone, Debug)]
pub struct LocalSnapshotListing {
    pub entries: Vec<LocalSnapshotEntry>,
    pub repeatedly_failing: bool,
}
#[derive(Clone, Debug, PartialEq)]
pub struct ChangeBatch {
    pub generation: i64,
    pub changed: Vec<String>,
    pub deleted: Vec<String>,
    pub shopping_changed: bool,
    pub conflicts_changed: bool,
}
#[derive(Clone, Debug, PartialEq)]
pub enum CollectionEvent {
    Snapshot(CollectionSnapshot),
    Change(ChangeBatch),
}
#[derive(Clone, Debug, PartialEq)]
pub enum DuplicateChoice {
    KeepBoth,
    Replace { id: String },
}
#[derive(Clone, Debug, PartialEq)]
pub enum ShoppingEdit {
    AddManual {
        text: String,
    },
    Edit {
        id: String,
        text: String,
    },
    Check {
        ids: Vec<String>,
        checked: bool,
    },
    Remove {
        ids: Vec<String>,
    },
    Move {
        id: String,
        category_id: String,
        before_id: Option<String>,
    },
    ReorderItems {
        category_id: String,
        ids: Vec<String>,
    },
    AddCategory {
        name: String,
    },
    RenameCategory {
        id: String,
        name: String,
    },
    DeleteCategory {
        id: String,
    },
    ReorderCategories {
        ids: Vec<String>,
    },
}
#[derive(Clone, Debug, PartialEq)]
pub struct RestoreReport {
    pub shopping_setup: bool,
    pub added: u32,
    pub updated: u32,
    pub skipped: u32,
    pub conflicts: Vec<String>,
}
#[derive(Clone, Debug, PartialEq)]
#[frb]
pub struct SyncPeer {
    #[frb(default = false)]
    pub pairing_pending: bool,
    pub id: String,
    pub name: String,
    pub address: String,
    pub last_sync: Option<u64>,
    pub caught_up: Option<bool>,
}
#[derive(Clone, Debug, PartialEq)]
pub struct SyncReport {
    pub id: String,
    pub name: String,
    pub status: String,
    pub error: Option<String>,
    pub retry_after_seconds: Option<u64>,
}
#[derive(Clone, Debug, PartialEq)]
#[frb]
pub struct SyncStatus {
    #[frb(default = false)]
    pub re_pair_required: bool,
    pub generation: Option<i64>,
    pub enabled: bool,
    pub active: bool,
    pub name: String,
    pub device_id: String,
    pub addresses: Vec<String>,
    pub port: u16,
    pub error: Option<String>,
    pub invitation_id: Option<String>,
    pub peers: Vec<SyncPeer>,
    pub reports: Vec<SyncReport>,
}
#[derive(Clone, Debug, PartialEq)]
pub enum ConflictChoice {
    Version { id: String },
    KeepAll,
}
#[frb(opaque)]
pub struct CleanupPreview {
    inner: services::CleanupPreview,
}
impl CleanupPreview {
    pub fn changed(&self) -> u32 {
        self.inner.changed
    }
    pub fn skipped_conflicts(&self) -> u32 {
        self.inner.skipped_conflicts
    }
}
#[derive(Clone, Debug, PartialEq)]
pub struct Candidate {
    pub recipe: Recipe,
    pub warnings: Vec<String>,
    pub ingredient_sources: Vec<String>,
    pub ai_review: Option<AiReview>,
}
#[derive(Clone, Debug, Default, PartialEq)]
pub struct AiReview {
    pub guessed_fields: Vec<String>,
    pub guessed_steps: Vec<u32>,
}
#[derive(Clone, Debug, PartialEq)]
pub struct ImportCandidates {
    pub candidates: Vec<Candidate>,
    pub warnings: Vec<String>,
    pub ordinary: bool,
}
#[derive(Clone, Debug, PartialEq)]
pub enum ErrorCode {
    Validation,
    StaleWrite,
    ConflictChanged,
    InvalidData,
    InvalidZip,
    Limit,
    Conflict,
    Cancelled,
    NoPrevious,
    Storage,
    Closed,
    Credentials,
    Provider,
    Quota,
    Transport,
}
#[derive(Clone, Debug, PartialEq)]
pub struct ServiceError {
    pub code: ErrorCode,
    pub message: String,
}
impl std::fmt::Display for ServiceError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str(&self.message)
    }
}
impl std::error::Error for ServiceError {}
fn sync_error(message: String) -> ServiceError {
    ServiceError {
        code: ErrorCode::Transport,
        message: message.chars().take(400).collect(),
    }
}

#[frb(opaque)]
pub struct Operation {
    pub(crate) inner: Arc<services::Operation>,
}
impl Operation {
    #[frb(sync)]
    pub fn new() -> Self {
        Self {
            inner: Arc::new(services::Operation::default()),
        }
    }
    #[frb(sync)]
    pub fn cancel(&self) -> bool {
        self.inner.cancel()
    }
}
impl Default for Operation {
    fn default() -> Self {
        Self::new()
    }
}
#[frb(opaque)]
pub struct RestorePreview {
    inner: services::RestorePreview,
}
impl RestorePreview {
    pub fn generation(&self) -> i64 {
        self.inner.generation
    }
    pub fn report(&self) -> RestoreReport {
        self.inner.report.clone().into()
    }
}
#[frb(opaque)]
#[derive(Clone)]
pub struct ShoppingUndo {
    pub(crate) inner: Arc<Mutex<Option<core::shopping::Undo>>>,
}
#[frb(non_opaque)]
pub struct ShoppingResult {
    pub snapshot: CollectionSnapshot,
    pub undo: ShoppingUndo,
}
#[frb(opaque)]
pub struct CoreSession {
    inner: Mutex<Option<Arc<services::Service>>>,
}
impl CoreSession {
    pub fn open(private_root: String) -> Result<Self, ServiceError> {
        Self::open_with_sync_port(private_root, None)
    }
    pub fn open_with_sync_port(
        private_root: String,
        port: Option<u16>,
    ) -> Result<Self, ServiceError> {
        struct Paths(String);
        impl core::adapters::AppPaths for Paths {
            fn private_root(&self) -> Result<std::path::PathBuf, String> {
                Ok(self.0.clone().into())
            }
        }
        Ok(Self {
            inner: Mutex::new(Some(Arc::new(match port {
                Some(port) => services::Service::open_with_port(&Paths(private_root), port)?,
                None => services::Service::open(&Paths(private_root))?,
            }))),
        })
    }
    pub fn close(&self) {
        self.inner.lock().unwrap().take();
    }
    pub fn snapshot(&self) -> Result<CollectionSnapshot, ServiceError> {
        Ok(self.service()?.snapshot()?.into())
    }
    pub fn sync_status(&self) -> Result<SyncStatus, ServiceError> {
        let value = self.service()?.sync_status().map_err(sync_error)?;
        let string = |v: &serde_json::Value| v.as_str().unwrap_or_default().to_string();
        Ok(SyncStatus {
            re_pair_required: value["rePairRequired"].as_bool().unwrap_or(false),
            generation: value["generation"].as_i64(),
            enabled: value["enabled"].as_bool().unwrap_or(false),
            active: value["active"].as_bool().unwrap_or(false),
            name: string(&value["name"]),
            device_id: string(&value["deviceId"]),
            addresses: value["addresses"]
                .as_array()
                .unwrap()
                .iter()
                .map(string)
                .collect(),
            port: value["port"].as_u64().unwrap() as u16,
            error: value["error"].as_str().map(str::to_owned),
            invitation_id: value["invitationId"].as_str().map(str::to_owned),
            peers: value["peers"]
                .as_array()
                .unwrap()
                .iter()
                .map(|p| SyncPeer {
                    pairing_pending: p["pairingPending"].as_bool().unwrap_or(false),
                    id: string(&p["id"]),
                    name: string(&p["name"]),
                    address: string(&p["address"]),
                    last_sync: p["lastSync"].as_u64(),
                    caught_up: p["caughtUp"].as_bool(),
                })
                .collect(),
            reports: value["reports"]
                .as_array()
                .unwrap()
                .iter()
                .map(|p| SyncReport {
                    id: string(&p["id"]),
                    name: string(&p["name"]),
                    status: string(&p["status"]),
                    error: p["error"].as_str().map(str::to_owned),
                    retry_after_seconds: p["retryAfterSeconds"].as_u64(),
                })
                .collect(),
        })
    }
    pub fn sync_host_active(&self, active: bool) -> Result<(), ServiceError> {
        self.service()?.sync_host_active(active).map_err(sync_error)
    }
    pub fn sync_dismiss_pairing_notice(&self) -> Result<(), ServiceError> {
        self.service()?
            .sync_dismiss_pairing_notice()
            .map_err(sync_error)
    }
    pub fn sync_configure(&self, enabled: bool, name: String) -> Result<(), ServiceError> {
        self.service()?
            .sync_configure(enabled, name)
            .map_err(sync_error)
    }
    pub fn sync_pairing(&self, pairing: bool) -> Result<(), ServiceError> {
        self.service()?.sync_pairing(pairing);
        Ok(())
    }
    pub fn sync_invitation(&self, address: String) -> Result<String, ServiceError> {
        self.service()?.sync_invitation(address).map_err(sync_error)
    }
    pub fn sync_pair(&self, code: String) -> Result<(), ServiceError> {
        self.service()?.sync_pair(code).map_err(sync_error)
    }
    pub fn sync_forget(&self, id: String) -> Result<(), ServiceError> {
        self.service()?.sync_forget(&id).map_err(sync_error)
    }
    pub fn sync_now(&self) -> Result<(), ServiceError> {
        self.service()?.sync_now().map_err(sync_error)
    }
    pub fn resolve_conflict(
        &self,
        id: String,
        heads: Vec<String>,
        choice: ConflictChoice,
    ) -> Result<CollectionSnapshot, ServiceError> {
        let choice = match choice {
            ConflictChoice::Version { id } => id,
            ConflictChoice::KeepAll => "keep-all".into(),
        };
        Ok(self.service()?.resolve(&id, &heads, &choice)?.into())
    }
    pub fn preview_cleanup(&self) -> Result<CleanupPreview, ServiceError> {
        Ok(CleanupPreview {
            inner: self.service()?.preview_cleanup()?,
        })
    }
    pub fn cleanup(
        &self,
        preview: &CleanupPreview,
        operation: &Operation,
    ) -> Result<CollectionSnapshot, ServiceError> {
        Ok(self
            .service()?
            .cleanup(&preview.inner, &operation.inner)?
            .into())
    }
    pub fn editor_units(&self) -> Result<Vec<String>, ServiceError> {
        Ok(self.service()?.editor_units()?)
    }
    pub fn detail(&self, id: String) -> Result<Option<Recipe>, ServiceError> {
        Ok(self
            .service()?
            .detail(&recipe::RecipeId(id))?
            .map(Into::into))
    }
    pub fn save(
        &self,
        generation: i64,
        base: Option<Recipe>,
        fields: RecipeFields,
        operation: &Operation,
    ) -> Result<CollectionSnapshot, ServiceError> {
        Ok(self
            .service()?
            .save(
                generation,
                base.map(TryInto::try_into).transpose()?,
                fields.try_into()?,
                &operation.inner,
            )?
            .into())
    }
    pub fn import_one(
        &self,
        generation: i64,
        fields: RecipeFields,
        choice: Option<DuplicateChoice>,
        operation: &Operation,
    ) -> Result<CollectionSnapshot, ServiceError> {
        let choice = choice.map(|c| match c {
            DuplicateChoice::KeepBoth => services::DuplicateChoice::KeepBoth,
            DuplicateChoice::Replace { id } => services::DuplicateChoice::Replace {
                id: recipe::RecipeId(id),
            },
        });
        Ok(self
            .service()?
            .import_one(generation, fields.try_into()?, choice, &operation.inner)?
            .into())
    }
    pub fn favorite(
        &self,
        generation: i64,
        id: String,
        value: bool,
        operation: &Operation,
    ) -> Result<CollectionSnapshot, ServiceError> {
        Ok(self
            .service()?
            .favorite(generation, &recipe::RecipeId(id), value, &operation.inner)?
            .into())
    }
    pub fn delete(
        &self,
        generation: i64,
        id: String,
        operation: &Operation,
    ) -> Result<CollectionSnapshot, ServiceError> {
        Ok(self
            .service()?
            .delete(generation, &recipe::RecipeId(id), &operation.inner)?
            .into())
    }
    pub fn rolling_snapshot_maintenance(&self) -> Result<bool, ServiceError> {
        Ok(self.service()?.rolling_snapshot_maintenance())
    }
    pub fn rolling_snapshots(&self) -> Result<LocalSnapshotListing, ServiceError> {
        let (entries, repeatedly_failing) = self.service()?.rolling_snapshots()?;
        Ok(LocalSnapshotListing {
            entries: entries
                .into_iter()
                .rev()
                .map(|e| LocalSnapshotEntry {
                    id: e.id,
                    created_at: e.created_at,
                    recipe_count: e.recipe_count,
                    omitted_count: e.omitted_count,
                    reason: e.reason,
                })
                .collect(),
            repeatedly_failing,
        })
    }
    pub fn rolling_snapshot_bytes(&self, id: String) -> Result<Vec<u8>, ServiceError> {
        Ok(self.service()?.rolling_snapshot_bytes(&id)?)
    }
    pub fn backup_report(&self, operation: &Operation) -> Result<RecipeBackup, ServiceError> {
        let report = self.service()?.backup_report(&operation.inner)?;
        Ok(RecipeBackup {
            bytes: report.bytes,
            omitted: report.omitted,
        })
    }
    pub fn discard_set_aside(
        &self,
        generation: i64,
        operation: &Operation,
    ) -> Result<CollectionSnapshot, ServiceError> {
        Ok(self
            .service()?
            .discard_set_aside(generation, &operation.inner)?
            .into())
    }
    pub fn backup(&self, operation: &Operation) -> Result<Vec<u8>, ServiceError> {
        Ok(self.service()?.backup(&operation.inner)?)
    }
    pub fn preview_restore(
        &self,
        bytes: Vec<u8>,
        operation: &Operation,
    ) -> Result<RestorePreview, ServiceError> {
        Ok(RestorePreview {
            inner: self.service()?.preview_restore(&bytes, &operation.inner)?,
        })
    }
    pub fn restore(
        &self,
        preview: &RestorePreview,
        operation: &Operation,
    ) -> Result<CollectionSnapshot, ServiceError> {
        Ok(self
            .service()?
            .restore(&preview.inner, &operation.inner)?
            .into())
    }
    pub fn recover(
        &self,
        generation: i64,
        operation: &Operation,
    ) -> Result<CollectionSnapshot, ServiceError> {
        Ok(self
            .service()?
            .recover(generation, &operation.inner)?
            .into())
    }
    pub fn add_shopping(
        &self,
        generation: i64,
        id: String,
        indices: Vec<u32>,
        operation: &Operation,
    ) -> Result<ShoppingResult, ServiceError> {
        Ok(self
            .service()?
            .add_shopping(
                generation,
                &recipe::RecipeId(id),
                &indices,
                &operation.inner,
            )?
            .into())
    }
    pub fn add_shopping_scaled(
        &self,
        generation: i64,
        id: String,
        indices: Vec<u32>,
        scale: u32,
        operation: &Operation,
    ) -> Result<ShoppingResult, ServiceError> {
        Ok(self
            .service()?
            .add_shopping_scaled(
                generation,
                &recipe::RecipeId(id),
                &indices,
                scale,
                &operation.inner,
            )?
            .into())
    }
    pub fn edit_shopping(
        &self,
        generation: i64,
        edit: ShoppingEdit,
        operation: &Operation,
    ) -> Result<ShoppingResult, ServiceError> {
        let edit = match edit {
            ShoppingEdit::AddManual { text } => services::ShoppingEdit::AddManual { text },
            ShoppingEdit::Edit { id, text } => services::ShoppingEdit::Edit { id, text },
            ShoppingEdit::Check { ids, checked } => services::ShoppingEdit::Check { ids, checked },
            ShoppingEdit::Remove { ids } => services::ShoppingEdit::Remove { ids },
            ShoppingEdit::Move {
                id,
                category_id,
                before_id,
            } => services::ShoppingEdit::Move {
                id,
                category_id,
                before_id,
            },
            ShoppingEdit::ReorderItems { category_id, ids } => {
                services::ShoppingEdit::ReorderItems { category_id, ids }
            }
            ShoppingEdit::AddCategory { name } => services::ShoppingEdit::AddCategory { name },
            ShoppingEdit::RenameCategory { id, name } => {
                services::ShoppingEdit::RenameCategory { id, name }
            }
            ShoppingEdit::DeleteCategory { id } => services::ShoppingEdit::DeleteCategory { id },
            ShoppingEdit::ReorderCategories { ids } => {
                services::ShoppingEdit::ReorderCategories { ids }
            }
        };
        Ok(self
            .service()?
            .edit_shopping(generation, edit, &operation.inner)?
            .into())
    }
    pub fn undo_shopping(
        &self,
        generation: i64,
        undo: &ShoppingUndo,
        operation: &Operation,
    ) -> Result<CollectionSnapshot, ServiceError> {
        let mut token = undo.inner.lock().unwrap();
        let value = token.as_ref().ok_or(services::Error::StaleWrite)?;
        let result = self
            .service()?
            .undo_shopping(generation, value, &operation.inner)?;
        token.take();
        Ok(result.into())
    }
}
impl CoreSession {
    #[frb(ignore)]
    fn service(&self) -> Result<Arc<services::Service>, ServiceError> {
        self.inner
            .lock()
            .unwrap()
            .clone()
            .ok_or_else(|| services::Error::Closed.into())
    }
}
pub fn parse_amount(written: String) -> Result<Amount, ServiceError> {
    Ok(recipe::Amount::parse_new(&written)
        .map_err(services::Error::from)?
        .into())
}
/// A null amount input retains the corresponding canonical amount exactly.
pub fn parse_editor_fields(
    fields: RecipeFields,
    amount_inputs: Vec<Option<String>>,
) -> Result<RecipeFields, ServiceError> {
    let raw = recipe::RecipeContent {
        title: fields.title,
        description: fields.description,
        servings: fields.servings,
        prep_time: fields.prep_time,
        cook_time: fields.cook_time,
        total_time: fields.total_time,
        source: fields.source,
        tags: fields.tags,
        notes: fields.notes,
        steps: fields.steps,
        ingredients: fields
            .ingredients
            .into_iter()
            .map(|row| {
                Ok(recipe::Ingredient {
                    amount: row.amount.try_into()?,
                    unit: row.unit,
                    name: row.name,
                    prep_note: row.prep_note,
                    optional: row.optional,
                    section: row.section,
                })
            })
            .collect::<Result<Vec<_>, ServiceError>>()?,
    };
    raw.parse_editor(&amount_inputs)
        .map(Into::into)
        .map_err(|error| ServiceError {
            code: ErrorCode::Validation,
            message: error.to_string(),
        })
}
pub fn parse_ingredient_paste(
    text: String,
    section: String,
) -> Result<Vec<PastedIngredient>, ServiceError> {
    recipe::paste::parse_ingredients(&text, &section)
        .map(|rows| {
            rows.into_iter()
                .map(|row| PastedIngredient {
                    ingredient: row.ingredient.into(),
                    original: row.original,
                    issue: row.issue,
                })
                .collect()
        })
        .map_err(|error| ServiceError {
            code: ErrorCode::Validation,
            message: error.to_string(),
        })
}
/// Canonical presentation only: never applies new-input snapping.
pub fn format_ingredient_amounts(
    ingredients: Vec<Ingredient>,
) -> Result<Vec<String>, ServiceError> {
    if ingredients.len() > 10_000 {
        return Err(services::Error::Limit.into());
    }
    ingredients
        .into_iter()
        .map(|ingredient| {
            let canonical: recipe::Ingredient = ingredient.try_into()?;
            Ok(canonical.amount.text())
        })
        .collect()
}
#[derive(Clone, Debug, PartialEq)]
pub struct ScaledRecipeView {
    pub quantities: Vec<String>,
    pub servings: String,
}
pub fn scale_recipe_view(
    fields: RecipeFields,
    scale: u32,
) -> Result<ScaledRecipeView, ServiceError> {
    let canonical: recipe::RecipeContent = fields.try_into()?;
    Ok(ScaledRecipeView {
        quantities: canonical
            .ingredients
            .iter()
            .map(|i| {
                recipe::scaling::quantity(i.amount, &i.unit, scale)
                    .map_err(|e| ServiceError::from(services::Error::from(e)))
            })
            .collect::<Result<_, _>>()?,
        servings: recipe::scaling::servings(&canonical.servings, scale)
            .map_err(services::Error::from)?,
    })
}
#[cfg(test)]
mod presentation_tests {
    use super::*;
    #[test]
    fn editor_changes_only_new_amounts_and_preserves_paste_warnings() {
        let pasted =
            parse_ingredient_paste("0.33 cup cream\n2-1 potatoes".into(), "Sauce".into()).unwrap();
        assert_eq!(
            pasted[0].ingredient.amount,
            Amount::Rational {
                numerator: 1,
                denominator: 3
            }
        );
        assert_eq!(pasted[0].ingredient.section, "Sauce");
        assert!(pasted[1].issue.is_some());
        assert_eq!(pasted[1].original, "2-1 potatoes");
        let mut row = pasted[0].ingredient.clone();
        row.amount = Amount::Rational {
            numerator: 33,
            denominator: 100,
        };
        let fields = RecipeFields {
            title: "  Cream  ".into(),
            description: String::new(),
            servings: " 2 large pancakes ".into(),
            prep_time: String::new(),
            cook_time: String::new(),
            total_time: String::new(),
            source: " https://example.com/cream ".into(),
            tags: vec![" Quick ".into(), "Quick".into()],
            notes: String::new(),
            ingredients: vec![row.clone(), row.clone(), row],
            steps: vec![" Mix ".into(), " ".into()],
        };
        let parsed = parse_editor_fields(
            fields.clone(),
            vec![None, Some("0.33".into()), Some("33/100".into())],
        )
        .unwrap();
        assert_eq!(
            parsed.ingredients[0].amount,
            Amount::Rational {
                numerator: 33,
                denominator: 100
            }
        );
        assert_eq!(
            parsed.ingredients[1].amount,
            Amount::Rational {
                numerator: 1,
                denominator: 3
            }
        );
        assert_eq!(
            parsed.ingredients[2].amount,
            Amount::Rational {
                numerator: 33,
                denominator: 100
            }
        );
        assert_eq!(parsed.title, "Cream");
        assert_eq!(parsed.servings, "2 large pancakes");
        assert_eq!(parsed.tags, ["Quick"]);
        assert_eq!(parsed.steps, ["Mix"]);
        assert!(parse_editor_fields(fields.clone(), vec![None]).is_err());
        let error = parse_editor_fields(fields, vec![None, None, Some("2-1".into())]).unwrap_err();
        assert_eq!(error.code, ErrorCode::Validation);
        assert!(error.message.contains("first amount"));
    }
    #[test]
    fn canonical_amount_display_does_not_snap() {
        let row = |amount| Ingredient {
            amount,
            unit: String::new(),
            name: "fixture".into(),
            prep_note: String::new(),
            optional: false,
            section: String::new(),
        };
        let formatted = format_ingredient_amounts(vec![
            row(Amount::Rational {
                numerator: 33,
                denominator: 100,
            }),
            row(Amount::Rational {
                numerator: 7,
                denominator: 3,
            }),
            row(Amount::ToTaste),
            row(Amount::Unspecified),
        ])
        .unwrap();
        assert_eq!(formatted, ["33/100", "2 1/3", "to taste", ""]);
        assert!(
            format_ingredient_amounts(vec![row(Amount::Rational {
                numerator: 1,
                denominator: 0
            })])
            .is_err()
        );
    }
}
pub fn parse_text(text: String) -> Result<ImportCandidates, ServiceError> {
    Ok(recipe::paste::parse_recipe_input(&text, &services::now())
        .map_err(|e| ServiceError {
            code: ErrorCode::Validation,
            message: e.to_string(),
        })?
        .into())
}
pub fn inspect_page(html: String, url: String) -> Result<ImportCandidates, ServiceError> {
    Ok(recipe::web::inspect_page(&html, &url, &services::now())
        .map_err(services::Error::from)?
        .imports
        .into())
}
pub fn page_readable_text(html: String) -> Result<String, ServiceError> {
    Ok(recipe::web::readable_text(&html).map_err(services::Error::from)?)
}
/// Bounded raw context only: no local recipe mapping or completeness checks.
pub fn page_ai_context(html: String) -> Result<String, ServiceError> {
    Ok(recipe::web::ai_context(&html).map_err(services::Error::from)?)
}
pub fn split_recipe_text(text: String) -> Result<Vec<String>, ServiceError> {
    Ok(recipe::paste::split_recipe_text(&text).map_err(services::Error::from)?)
}
pub fn export_text(recipe: Recipe) -> Result<String, ServiceError> {
    Ok(recipe::text::export_recipe(&recipe.try_into()?).map_err(services::Error::from)?)
}

pub fn ai_copy_prompt(existing_tags: Vec<String>) -> String {
    core::provider::copy_prompt(&prompt_tags(existing_tags))
}

#[cfg(test)]
mod smart_import_tests {
    use super::*;
    use serde_json::json;
    fn task() -> ProviderTask {
        ProviderTask::new(
            ProviderInput {
                text: "synthetic recipe".into(),
                source: String::new(),
                target_title: String::new(),
                photos: vec![],
                mode: ProviderMode::Recipe,
                existing_tags: vec![],
            },
            "mock-model".into(),
            &Operation::new(),
        )
        .unwrap()
    }
    fn reply(value: serde_json::Value) -> Vec<u8> {
        serde_json::to_vec(&json!({"status":"completed","steps":[{"type":"model_output","content":[{"type":"text","text":value.to_string()}]}]})).unwrap()
    }
    #[test]
    fn retry_keeps_specific_problem_and_partial_recipe_review() {
        let task = task();
        task.request().unwrap();
        assert!(matches!(
            task.accept(200, reply(json!({}))).unwrap(),
            ProviderOutput::Retry
        ));
        assert!(
            task.validation_problem()
                .unwrap()
                .contains("no title, no ingredients and no steps")
        );
        let request: serde_json::Value = serde_json::from_slice(&task.request().unwrap()).unwrap();
        assert!(
            request["system_instruction"]
                .as_str()
                .unwrap()
                .contains("no title, no ingredients and no steps")
        );
        let result = task.accept(200, reply(json!({"title":"Rolls","ingredients":[{"name":"flour","amount":"4 -5","unit":"cups"}],"aiGuessedFields":null}))).unwrap();
        let ProviderOutput::Recipe(recipe) = result else {
            panic!("recipe expected")
        };
        assert_eq!(recipe.fields.ingredients[0].unit, "cup");
        assert!(matches!(
            recipe.fields.ingredients[0].amount,
            Amount::Range {
                lower_numerator: 4,
                upper_numerator: 5,
                ..
            }
        ));
        assert!(
            !task
                .warnings()
                .iter()
                .any(|w| w.contains("flour") && w.contains("could not be parsed"))
        );
        assert!(task.review().guessed_fields.is_empty());
    }
    #[test]
    fn non_ok_status_and_second_truncation_keep_specific_messages() {
        let task = task();
        task.request().unwrap();
        let error = task
            .accept(
                200,
                reply(json!({"status":"retrieval_failed","reason":"The page denied access."})),
            )
            .unwrap_err();
        assert!(error.message.contains("denied access"));
        assert!(task.request().is_err());
        let task = self::task();
        task.request().unwrap();
        assert!(matches!(
            task.accept(200, br#"{"status":"incomplete"}"#.to_vec())
                .unwrap(),
            ProviderOutput::Retry
        ));
        task.request().unwrap();
        assert!(
            task.accept(200, br#"{"status":"incomplete"}"#.to_vec())
                .unwrap_err()
                .message
                .contains("cut off")
        );
    }
}
pub fn ai_json_prompt(mode: ProviderMode, photos: bool, existing_tags: Vec<String>) -> String {
    core::provider::json_prompt(
        &match mode {
            ProviderMode::Recipe => core::provider::Mode::Recipe,
            ProviderMode::UrlRecipe => core::provider::Mode::UrlRecipe,
        },
        photos,
        &prompt_tags(existing_tags),
    )
}
fn prompt_tags(existing_tags: Vec<String>) -> Vec<String> {
    core::provider::allowed_tags(&core::provider::Input {
        text: String::new(),
        source: String::new(),
        target_title: String::new(),
        photos: vec![],
        mode: core::provider::Mode::Recipe,
        existing_tags,
    })
}

#[derive(Clone, Debug, PartialEq)]
pub enum ProviderMode {
    Recipe,
    UrlRecipe,
}
#[derive(Clone, Debug, PartialEq)]
pub struct PreparedPhoto {
    pub mime_type: String,
    pub bytes: Vec<u8>,
}
#[derive(Clone, Debug, PartialEq)]
pub struct ProviderInput {
    pub text: String,
    pub source: String,
    pub target_title: String,
    pub photos: Vec<PreparedPhoto>,
    pub mode: ProviderMode,
    pub existing_tags: Vec<String>,
}
#[derive(Clone, Debug, PartialEq)]
pub enum ProviderOutput {
    Retry,
    Recipe(Recipe),
}
/// Secret-free adapter boundary. C7/C9 provide the native HTTP/secure-store host.
/// One task owns one operation token and at most two provider requests.
#[frb(opaque)]
pub struct ProviderTask {
    input: core::provider::Input,
    model: String,
    operation: Arc<services::Operation>,
    state: Mutex<(u8, bool)>,
    review: Mutex<AiReview>,
    warnings: Mutex<Vec<String>>,
    problems: Mutex<Option<String>>,
}
impl ProviderTask {
    pub fn new(
        input: ProviderInput,
        model: String,
        operation: &Operation,
    ) -> Result<Self, ServiceError> {
        let input = core::provider::Input {
            text: input.text,
            source: input.source,
            target_title: input.target_title,
            existing_tags: input.existing_tags,
            photos: input
                .photos
                .into_iter()
                .map(|p| core::provider::Photo {
                    mime_type: p.mime_type,
                    bytes: p.bytes,
                })
                .collect(),
            mode: match input.mode {
                ProviderMode::Recipe => core::provider::Mode::Recipe,
                ProviderMode::UrlRecipe => core::provider::Mode::UrlRecipe,
            },
        };
        operation.inner.check()?;
        core::provider::request(&input, &model, false)?;
        Ok(Self {
            input,
            model,
            operation: operation.inner.clone(),
            state: Mutex::new((0, false)),
            review: Mutex::new(AiReview::default()),
            warnings: Mutex::new(Vec::new()),
            problems: Mutex::new(None),
        })
    }
    pub fn request(&self) -> Result<Vec<u8>, ServiceError> {
        self.operation.check()?;
        let mut state = self.state.lock().unwrap();
        if state.0 >= 2 || state.1 {
            return Err(services::Error::StaleWrite.into());
        }
        let request = core::provider::request_with_problems(
            &self.input,
            &self.model,
            self.problems.lock().unwrap().as_deref(),
        )?;
        state.1 = true;
        Ok(request)
    }
    pub fn accept(&self, status: u16, bytes: Vec<u8>) -> Result<ProviderOutput, ServiceError> {
        self.operation.check()?;
        let mut state = self.state.lock().unwrap();
        if !state.1 || state.0 >= 2 {
            return Err(services::Error::StaleWrite.into());
        }
        state.1 = false;
        state.0 += 1;
        if !(200..300).contains(&status) {
            state.0 = 2;
            let mut error: ServiceError = core::provider::status_error(status, &bytes).into();
            if let Some(reason) = core::provider::failure_reason(&bytes) {
                error.message = reason;
            }
            return Err(error);
        }
        match core::provider::validated_response(&bytes) {
            Err(problem) => {
                *self.problems.lock().unwrap() = Some(problem.message.clone());
                if problem.retryable && state.0 == 1 {
                    Ok(ProviderOutput::Retry)
                } else {
                    state.0 = 2;
                    Err(ServiceError {
                        code: ErrorCode::Provider,
                        message: problem.message,
                    })
                }
            }
            Ok((mut recipe, warnings)) => {
                state.0 = 2;
                *self.warnings.lock().unwrap() = warnings;
                let review = core::provider::review_response(&bytes, &self.input, &mut recipe)
                    .unwrap_or_default();
                *self.review.lock().unwrap() = AiReview {
                    guessed_fields: review.ai_guessed_fields,
                    guessed_steps: review.ai_guessed_steps,
                };
                Ok(ProviderOutput::Recipe(recipe.into()))
            }
        }
    }
    pub fn warnings(&self) -> Vec<String> {
        self.warnings.lock().unwrap().clone()
    }
    pub fn validation_problem(&self) -> Option<String> {
        self.problems.lock().unwrap().clone()
    }
    pub fn review(&self) -> AiReview {
        self.review.lock().unwrap().clone()
    }
}

/// Holds only a weak service reference between polls; closing the session closes the stream.
pub fn subscribe(
    session: &CoreSession,
    operation: &Operation,
    sink: crate::frb_generated::StreamSink<CollectionEvent>,
) -> Result<(), ServiceError> {
    operation.inner.check()?;
    let cancelled = operation.inner.clone();
    let service = session.service()?;
    let subscription = service.subscribe()?;
    let weak = Arc::downgrade(&service);
    sink.add(CollectionEvent::Snapshot(subscription.snapshot.into()))
        .map_err(|_| services::Error::Closed)?;
    std::thread::spawn(move || {
        while weak.strong_count() > 0 && cancelled.check().is_ok() {
            match subscription
                .receiver
                .recv_timeout(std::time::Duration::from_millis(100))
            {
                Ok(change) => {
                    if sink.add(CollectionEvent::Change(change.into())).is_err() {
                        break;
                    }
                }
                Err(std::sync::mpsc::RecvTimeoutError::Timeout) => (),
                Err(_) => break,
            }
        }
    });
    Ok(())
}
