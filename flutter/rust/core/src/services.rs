//! Typed commands over a single serialized Flutter-owned session.
use crate::{
    adapters::AppPaths,
    backup,
    recipe::{self, Recipe, RecipeContent, RecipeId},
    rolling_snapshots,
    session::Session,
    shopping, storage, sync_store,
};
use std::collections::HashSet;
use std::sync::{
    Arc, Mutex,
    atomic::{AtomicU8, Ordering},
    mpsc,
};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Error {
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
    UrlRetrieval,
}
impl std::fmt::Display for Error {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str(match self {
            Self::Validation => "Check the recipe fields.",
            Self::StaleWrite => "The collection changed. Refresh before saving.",
            Self::ConflictChanged => "The conflict changed. Review its current versions.",
            Self::InvalidData => "The data is corrupt or unsupported.",
            Self::InvalidZip => "The recipe ZIP is invalid or unsupported.",
            Self::Limit => "The data exceeds its limit.",
            Self::Conflict => "Resolve recipe conflicts before this action.",
            Self::Cancelled => "Operation cancelled.",
            Self::NoPrevious => "No previous save is available.",
            Self::Storage => "The local store is unavailable.",
            Self::Closed => "The session is closed.",
            Self::Credentials => "Check the Gemini key and model.",
            Self::Provider => "The recipe response could not be read reliably.",
            Self::Quota => "Gemini is busy or its quota was reached.",
            Self::Transport => "The provider could not be reached.",
            Self::UrlRetrieval => {
                "Gemini could not retrieve this page. Paste the recipe text or use a photo."
            }
        })
    }
}
impl std::error::Error for Error {}
impl From<recipe::RuleError> for Error {
    fn from(_: recipe::RuleError) -> Self {
        Self::Validation
    }
}
pub type Result<T> = std::result::Result<T, Error>;
fn db_error(e: String) -> Error {
    if e.contains("STALE_WRITE") {
        Error::StaleWrite
    } else if e.contains("conflict") {
        Error::Conflict
    } else if e.contains("limit") {
        Error::Limit
    } else {
        Error::Storage
    }
}

#[derive(Default)]
pub struct Operation {
    state: AtomicU8,
}
impl Operation {
    pub fn cancel(&self) -> bool {
        self.state
            .compare_exchange(0, 1, Ordering::AcqRel, Ordering::Acquire)
            .is_ok()
    }
    pub fn check(&self) -> Result<()> {
        if self.state.load(Ordering::Acquire) == 1 {
            Err(Error::Cancelled)
        } else {
            Ok(())
        }
    }
    fn commit<T>(&self, work: impl FnOnce() -> Result<T>) -> Result<T> {
        // Linearization point: cancellation is accepted until commit begins.
        // Once committing, return the durable outcome; cancel never blocks Dart.
        self.state
            .compare_exchange(0, 2, Ordering::AcqRel, Ordering::Acquire)
            .map_err(|s| {
                if s == 1 {
                    Error::Cancelled
                } else {
                    Error::StaleWrite
                }
            })?;
        let result = work();
        self.state
            .store(if result.is_ok() { 3 } else { 0 }, Ordering::Release);
        result
    }
}
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Summary {
    pub id: RecipeId,
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
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ConflictVersion {
    pub id: String,
    pub recipe: Option<Recipe>,
    pub deleted_at: Option<String>,
}
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Conflict {
    pub recipe_id: RecipeId,
    pub versions: Vec<ConflictVersion>,
}
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Snapshot {
    pub generation: i64,
    pub summaries: Vec<Summary>,
    pub shopping: Vec<shopping::Item>,
    pub shopping_categories: Vec<crate::shopping_categories::Category>,
    pub conflicts: Vec<Conflict>,
    pub has_previous: bool,
    pub set_aside_count: u32,
}
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Change {
    pub generation: i64,
    pub changed: Vec<RecipeId>,
    pub deleted: Vec<RecipeId>,
    pub shopping_changed: bool,
    pub conflicts_changed: bool,
}
pub struct Subscription {
    pub snapshot: Snapshot,
    pub receiver: mpsc::Receiver<Change>,
}
#[derive(Debug, Clone)]
pub enum DuplicateChoice {
    KeepBoth,
    Replace { id: RecipeId },
}
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct RestoreReport {
    pub shopping_setup: bool,
    pub added: u32,
    pub updated: u32,
    pub skipped: u32,
    pub conflicts: Vec<RecipeId>,
}
pub struct RecipeBackup {
    pub bytes: Vec<u8>,
    pub omitted: u32,
}
pub struct RestorePreview {
    pub generation: i64,
    pub report: RestoreReport,
    recipes: Vec<Recipe>,
    shopping_setup: Option<crate::shopping_categories::Setup>,
}
pub struct CleanupPreview {
    pub generation: i64,
    pub changed: u32,
    pub skipped_conflicts: u32,
    recipes: Vec<Recipe>,
}
#[derive(Debug, Clone)]
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
pub struct ShoppingResult {
    pub snapshot: Snapshot,
    pub undo: shopping::Undo,
}

pub struct Service {
    session: Session,
    subscribers: Arc<Mutex<Vec<mpsc::SyncSender<Change>>>>,
}
impl Service {
    pub fn open(paths: &impl AppPaths) -> Result<Self> {
        Self::from_session(Session::open(paths).map_err(db_error)?)
    }
    pub fn open_with_port(paths: &impl AppPaths, port: u16) -> Result<Self> {
        Self::from_session(Session::open_with_port(paths, port).map_err(db_error)?)
    }
    fn from_session(session: Session) -> Result<Self> {
        let subscribers: Arc<Mutex<Vec<mpsc::SyncSender<Change>>>> = Arc::new(Mutex::new(vec![]));
        let output = subscribers.clone();
        session.sync.on_change(Arc::new(move |generation, ids| {
            let change = Change {
                generation,
                changed: ids.into_iter().map(RecipeId).collect(),
                deleted: vec![],
                shopping_changed: false,
                conflicts_changed: true,
            };
            output
                .lock()
                .unwrap()
                .retain(|tx| tx.try_send(change.clone()).is_ok());
        }));
        if let Ok(mut db) = session.connection() {
            rolling_snapshots::attempt(&mut db, "automatic");
        }
        Ok(Self {
            session,
            subscribers,
        })
    }
    pub fn editor_units(&self) -> Result<Vec<String>> {
        let mut db = self.session.connection().map_err(db_error)?;
        Ok(
            Self::recipes(&storage::load(&mut db).map_err(db_error)?.book)?
                .into_iter()
                .flat_map(|r| r.content.ingredients.into_iter().map(|i| i.unit))
                .collect(),
        )
    }
    pub fn sync_status(&self) -> std::result::Result<serde_json::Value, String> {
        self.session.sync.status()
    }
    pub fn sync_host_active(&self, active: bool) -> std::result::Result<(), String> {
        self.session.sync.host_active(active)
    }
    pub fn sync_configure(&self, enabled: bool, name: String) -> std::result::Result<(), String> {
        self.session.sync.configure(enabled, name)
    }
    pub fn sync_pairing(&self, pairing: bool) {
        self.session.sync.pairing(pairing);
    }
    pub fn sync_dismiss_pairing_notice(&self) -> std::result::Result<(), String> {
        self.session.sync.dismiss_pairing_notice()
    }
    pub fn sync_invitation(&self, address: String) -> std::result::Result<String, String> {
        self.session.sync.invitation(address)
    }
    pub fn sync_pair(&self, code: String) -> std::result::Result<(), String> {
        self.session.sync.pair(code)
    }
    pub fn sync_forget(&self, id: &str) -> std::result::Result<(), String> {
        self.session.sync.forget(id)
    }
    pub fn sync_now(&self) -> std::result::Result<(), String> {
        self.session.sync.manual()
    }
    pub fn resolve(&self, id: &str, heads: &[String], choice: &str) -> Result<Snapshot> {
        let mut db = self.session.connection().map_err(db_error)?;
        sync_store::resolve(&mut db, id, heads, choice, &now()).map_err(|e| {
            if e.starts_with("Conflict") || e == "Unknown version" {
                Error::ConflictChanged
            } else {
                db_error(e)
            }
        })?;
        let s = storage::load(&mut db).map_err(db_error)?;
        let reply = Self::snapshot_from(&db, &s)?;
        drop(db);
        self.session.sync.local_recipe_changed();
        Ok(reply)
    }
    pub fn preview_cleanup(&self) -> Result<CleanupPreview> {
        let mut db = self.session.connection().map_err(db_error)?;
        let snapshot = storage::load(&mut db).map_err(db_error)?;
        let conflicts = Self::conflicts(&db)?;
        let mut changed = vec![];
        for mut r in Self::recipes(&snapshot.book)? {
            if conflicts.iter().any(|c| c.recipe_id == r.id) {
                continue;
            }
            let content = r
                .content
                .parse_editor(&vec![None; r.content.ingredients.len()])?;
            if content != r.content {
                r.content = content;
                changed.push(r);
            }
        }
        Ok(CleanupPreview {
            generation: snapshot.generation,
            changed: changed.len() as u32,
            skipped_conflicts: conflicts.len() as u32,
            recipes: changed,
        })
    }
    pub fn cleanup(&self, preview: &CleanupPreview, operation: &Operation) -> Result<Snapshot> {
        self.mutate(preview.generation, operation, |book| {
            // One ordinary successor per changed recipe, in a single transaction.
            // Generation binds confirmation to the exact preview, including conflicts.
            for original in &preview.recipes {
                let mut r = original.clone();
                r.revision = r.revision.checked_add(1).ok_or(Error::Limit)?;
                r.updated_at = now();
                r.validate()?;
                put_recipe(book, r)?;
            }
            Ok(())
        })
    }
    fn recipes(book: &storage::Book) -> Result<Vec<Recipe>> {
        let mut recipes = book
            .recipes
            .iter()
            .map(|v| {
                Recipe::from_json(&serde_json::to_vec(v).map_err(|_| Error::InvalidData)?)
                    .map_err(|_| Error::InvalidData)
            })
            .collect::<Result<Vec<_>>>()?;
        recipes.sort_by(|a, b| a.id.0.cmp(&b.id.0));
        Ok(recipes)
    }
    fn shopping(book: &storage::Book) -> Result<Vec<shopping::Item>> {
        let mut items: Vec<shopping::Item> = book
            .shopping
            .iter()
            .map(|v| serde_json::from_value(v.clone()).map_err(|_| Error::InvalidData))
            .collect::<Result<Vec<_>>>()?;
        book.shopping_setup.validate()?;
        for item in &mut items {
            if item.category_id.is_empty() {
                item.category_id = book.shopping_setup.classify(&item.name);
            } else if !book.shopping_setup.contains(&item.category_id) {
                item.category_id = crate::shopping_categories::OTHER.into();
            }
        }
        shopping::validate(&items)?;
        Ok(items)
    }
    fn conflicts(db: &rusqlite::Connection) -> Result<Vec<Conflict>> {
        let value = sync_store::conflicts(db).map_err(db_error)?;
        value
            .as_array()
            .ok_or(Error::InvalidData)?
            .iter()
            .map(|c| {
                let recipe_id = RecipeId(c["recipeId"].as_str().ok_or(Error::InvalidData)?.into());
                let versions = c["versions"]
                    .as_array()
                    .ok_or(Error::InvalidData)?
                    .iter()
                    .map(|v| {
                        Ok(ConflictVersion {
                            id: v["id"].as_str().ok_or(Error::InvalidData)?.into(),
                            recipe: if v["recipe"].is_null() {
                                None
                            } else {
                                Some(Recipe::from_json(
                                    &serde_json::to_vec(&v["recipe"])
                                        .map_err(|_| Error::InvalidData)?,
                                )?)
                            },
                            deleted_at: v["deletedAt"].as_str().map(String::from),
                        })
                    })
                    .collect::<Result<_>>()?;
                Ok(Conflict {
                    recipe_id,
                    versions,
                })
            })
            .collect()
    }
    fn snapshot_from(db: &rusqlite::Connection, s: &storage::Snapshot) -> Result<Snapshot> {
        Ok(Snapshot {
            generation: s.generation,
            set_aside_count: s.set_aside.len() as u32,
            summaries: Self::recipes(&s.book)?
                .into_iter()
                .map(|r| Summary {
                    id: r.id,
                    title: r.content.title,
                    description: r.content.description,
                    ingredients: r
                        .content
                        .ingredients
                        .iter()
                        .map(|i| i.name.clone())
                        .collect(),
                    tags: r.content.tags,
                    notes: r.content.notes,
                    favorite: r.favorite,
                    created_at: r.created_at,
                    updated_at: r.updated_at,
                    servings: r.content.servings,
                    prep_time: r.content.prep_time,
                    cook_time: r.content.cook_time,
                    total_time: r.content.total_time,
                    revision: r.revision,
                })
                .collect(),
            shopping: Self::shopping(&s.book)?,
            shopping_categories: s.book.shopping_setup.categories.clone(),
            conflicts: Self::conflicts(db)?,
            has_previous: storage::previous(db).map_err(db_error)?.is_some(),
        })
    }
    pub fn snapshot(&self) -> Result<Snapshot> {
        let mut db = self.session.connection().map_err(db_error)?;
        let s = storage::load(&mut db).map_err(db_error)?;
        Self::snapshot_from(&db, &s)
    }
    /// Registration and snapshot occur while holding the same lock as commits.
    /// A slow subscriber is disconnected on overflow and must obtain a new snapshot.
    pub fn subscribe(&self) -> Result<Subscription> {
        let mut db = self.session.connection().map_err(db_error)?;
        let s = storage::load(&mut db).map_err(db_error)?;
        let snapshot = Self::snapshot_from(&db, &s)?;
        let (tx, receiver) = mpsc::sync_channel(64);
        self.subscribers.lock().map_err(|_| Error::Closed)?.push(tx);
        Ok(Subscription { snapshot, receiver })
    }
    pub fn detail(&self, id: &RecipeId) -> Result<Option<Recipe>> {
        let mut db = self.session.connection().map_err(db_error)?;
        Ok(
            Self::recipes(&storage::load(&mut db).map_err(db_error)?.book)?
                .into_iter()
                .find(|r| &r.id == id),
        )
    }
    fn mutate(
        &self,
        generation: i64,
        operation: &Operation,
        edit: impl FnOnce(&mut storage::Book) -> Result<()>,
    ) -> Result<Snapshot> {
        self.mutate_with_reason(generation, operation, "automatic", edit)
    }
    fn mutate_with_reason(
        &self,
        generation: i64,
        operation: &Operation,
        reason: &str,
        edit: impl FnOnce(&mut storage::Book) -> Result<()>,
    ) -> Result<Snapshot> {
        operation.check()?;
        let mut db = self.session.connection().map_err(db_error)?;
        let old = storage::load(&mut db).map_err(db_error)?;
        if generation != old.generation {
            return Err(Error::StaleWrite);
        }
        let old_recipes = Self::recipes(&old.book)?;
        Self::shopping(&old.book)?;
        let mut book = old.book.clone();
        edit(&mut book)?;
        let recipes = Self::recipes(&book)?;
        backup::validate_collection(&recipes)?;
        Self::shopping(&book)?;
        // Construct/validate the reply before commit. A durable write must never
        // become an apparent failure due to projection validation afterwards.
        let mut reply = Self::snapshot_from(
            &db,
            &storage::Snapshot {
                generation,
                book: book.clone(),
                set_aside: old
                    .set_aside
                    .iter()
                    .filter(|id| !book.recipes.iter().any(|r| r["id"] == **id))
                    .cloned()
                    .collect(),
            },
        )?;
        operation.commit(|| {
            rolling_snapshots::attempt(&mut db, reason);
            let generation = storage::save(&mut db, generation, &book, &now()).map_err(db_error)?;
            // A restore must retain its pre-operation archive until a later snapshot.
            if reason != "before_restore" {
                rolling_snapshots::attempt(&mut db, "automatic");
            }
            let change = Change {
                generation,
                changed: recipes
                    .iter()
                    .filter(|r| !old_recipes.contains(r))
                    .map(|r| r.id.clone())
                    .collect(),
                deleted: Self::recipes(&old.book)?
                    .into_iter()
                    .filter(|r| !recipes.iter().any(|n| n.id == r.id))
                    .map(|r| r.id)
                    .collect(),
                shopping_changed: old.book.shopping != book.shopping
                    || old.book.shopping_setup != book.shopping_setup,
                conflicts_changed: reply.set_aside_count != old.set_aside.len() as u32,
            };
            // Once committed, cancellation cannot turn success into failure.
            self.subscribers
                .lock()
                .unwrap()
                .retain(|tx| tx.try_send(change.clone()).is_ok());
            if !change.changed.is_empty() || !change.deleted.is_empty() {
                self.session.sync.local_recipe_changed();
            }
            reply.generation = generation;
            reply.has_previous |= old.set_aside.is_empty();
            Ok(reply)
        })
    }
    pub fn save(
        &self,
        generation: i64,
        base: Option<Recipe>,
        mut content: RecipeContent,
        operation: &Operation,
    ) -> Result<Snapshot> {
        content.validate()?;
        content.tidy_names();
        self.mutate(generation, operation, |book| {
            let mut recipe = if let Some(base) = base {
                let current = Self::recipes(book)?
                    .into_iter()
                    .find(|r| r.id == base.id)
                    .ok_or(Error::StaleWrite)?;
                if current != base {
                    return Err(Error::StaleWrite);
                }
                current
            } else {
                Recipe::new(content.clone(), &now())?
            };
            if book.recipes.iter().any(|r| r["id"] == recipe.id.0) {
                recipe.revision = recipe.revision.checked_add(1).ok_or(Error::Limit)?;
            }
            recipe.content = content;
            recipe.updated_at = now();
            recipe.validate()?;
            put_recipe(book, recipe)
        })
    }
    pub fn import_one(
        &self,
        generation: i64,
        content: RecipeContent,
        choice: Option<DuplicateChoice>,
        operation: &Operation,
    ) -> Result<Snapshot> {
        content.validate()?;
        self.mutate(generation, operation, |book| {
            let matches = Self::recipes(book)?
                .into_iter()
                .filter(|r| {
                    recipe::model::normalize_name(&r.content.title)
                        == recipe::model::normalize_name(&content.title)
                })
                .collect::<Vec<_>>();
            let mut imported = Recipe::new(content, &now())?;
            match choice {
                None if !matches.is_empty() => return Err(Error::Conflict),
                Some(DuplicateChoice::Replace { id }) => {
                    let old = matches
                        .iter()
                        .find(|r| r.id == id)
                        .ok_or(Error::StaleWrite)?;
                    imported.id = old.id.clone();
                    imported.created_at = old.created_at.clone();
                    imported.revision = old.revision.checked_add(1).ok_or(Error::Limit)?;
                }
                _ => (),
            }
            put_recipe(book, imported)
        })
    }
    pub fn favorite(
        &self,
        generation: i64,
        id: &RecipeId,
        value: bool,
        operation: &Operation,
    ) -> Result<Snapshot> {
        self.mutate(generation, operation, |book| {
            let mut recipe = Self::recipes(book)?
                .into_iter()
                .find(|r| &r.id == id)
                .ok_or(Error::StaleWrite)?;
            recipe.favorite = value;
            recipe.updated_at = now();
            recipe.revision += 1;
            put_recipe(book, recipe)
        })
    }
    pub fn delete(
        &self,
        generation: i64,
        id: &RecipeId,
        operation: &Operation,
    ) -> Result<Snapshot> {
        self.mutate(generation, operation, |book| {
            let i = book
                .recipes
                .iter()
                .position(|r| r["id"] == id.0)
                .ok_or(Error::StaleWrite)?;
            book.recipes.remove(i);
            book.deleted_recipes.retain(|r| r["id"] != id.0);
            book.deleted_recipes
                .push(serde_json::json!({"id":id.0,"deletedAt":now()}));
            Ok(())
        })
    }
    pub fn rolling_snapshot_maintenance(&self) -> bool {
        if let Ok(mut db) = self.session.connection() {
            rolling_snapshots::attempt(&mut db, "automatic");
            return rolling_snapshots::repeatedly_failing(&db);
        }
        false
    }
    pub fn rolling_snapshots(&self) -> Result<(Vec<rolling_snapshots::Entry>, bool)> {
        let db = self.session.connection().map_err(db_error)?;
        Ok((
            rolling_snapshots::list(&db).map_err(db_error)?,
            rolling_snapshots::repeatedly_failing(&db),
        ))
    }
    pub fn rolling_snapshot_bytes(&self, id: &str) -> Result<Vec<u8>> {
        let db = self.session.connection().map_err(db_error)?;
        rolling_snapshots::read(&db, id).map_err(db_error)
    }
    pub fn backup(&self, operation: &Operation) -> Result<Vec<u8>> {
        Ok(self.backup_report(operation)?.bytes)
    }
    pub fn backup_report(&self, operation: &Operation) -> Result<RecipeBackup> {
        operation.check()?;
        let (recipes, shopping_setup, omitted) = {
            let mut db = self.session.connection().map_err(db_error)?;
            let values = storage::backup_recipes(&mut db).map_err(db_error)?;
            let recipes = Self::recipes(&storage::Book {
                recipes: values,
                ..Default::default()
            })?;
            let snapshot = storage::load(&mut db).map_err(db_error)?;
            (
                recipes,
                snapshot.book.shopping_setup,
                snapshot.set_aside.len() as u32,
            )
        };
        let bytes = backup::write_with_setup(&recipes, Some(&shopping_setup))?;
        operation.check()?;
        Ok(RecipeBackup { bytes, omitted })
    }
    pub fn discard_set_aside(&self, generation: i64, operation: &Operation) -> Result<Snapshot> {
        operation.check()?;
        let mut db = self.session.connection().map_err(db_error)?;
        operation.commit(|| {
            if storage::snapshot(&db).map_err(db_error)?.generation != generation {
                return Err(Error::StaleWrite);
            }
            rolling_snapshots::attempt(&mut db, "before_discard");
            storage::discard_set_aside(&mut db, generation, &now()).map_err(db_error)?;
            let s = storage::load(&mut db).map_err(db_error)?;
            let reply = Self::snapshot_from(&db, &s)?;
            let change = Change {
                generation: s.generation,
                changed: vec![],
                deleted: vec![],
                shopping_changed: false,
                conflicts_changed: true,
            };
            self.subscribers
                .lock()
                .unwrap()
                .retain(|tx| tx.try_send(change.clone()).is_ok());
            self.session.sync.local_recipe_changed();
            Ok(reply)
        })
    }
    pub fn preview_restore(&self, bytes: &[u8], operation: &Operation) -> Result<RestorePreview> {
        operation.check()?;
        let (recipes, shopping_setup) = backup::read_with_setup(bytes)?;
        let mut db = self.session.connection().map_err(db_error)?;
        let s = storage::load(&mut db).map_err(db_error)?;
        let mut report = merge_recipes(&mut s.book.clone(), &recipes)?;
        report.shopping_setup = shopping_setup.is_some();
        operation.check()?;
        Ok(RestorePreview {
            generation: s.generation,
            report,
            recipes,
            shopping_setup,
        })
    }
    pub fn restore(&self, preview: &RestorePreview, operation: &Operation) -> Result<Snapshot> {
        self.mutate_with_reason(preview.generation, operation, "before_restore", |book| {
            merge_recipes(book, &preview.recipes)?;
            if let Some(setup) = &preview.shopping_setup {
                let mut items = Self::shopping(book)?;
                for item in &mut items {
                    if !setup.contains(&item.category_id) {
                        item.category_id = crate::shopping_categories::OTHER.into();
                    }
                }
                book.shopping = items
                    .into_iter()
                    .map(|i| serde_json::to_value(i).map_err(|_| Error::InvalidData))
                    .collect::<Result<_>>()?;
                book.shopping_setup = setup.clone();
            }
            Ok(())
        })
    }
    pub fn recover(&self, generation: i64, operation: &Operation) -> Result<Snapshot> {
        // Read previous under the mutation lock so another commit cannot replace it.
        let previous = {
            let db = self.session.connection().map_err(db_error)?;
            storage::previous(&db)
                .map_err(db_error)?
                .ok_or(Error::NoPrevious)?
        };
        let mut recovered: storage::Book =
            serde_json::from_value(previous["book"].clone()).map_err(|_| Error::InvalidData)?;
        self.mutate(generation, operation, |book| {
            let current = Self::recipes(book)?;
            for value in &mut recovered.recipes {
                let mut r =
                    Recipe::from_json(&serde_json::to_vec(value).map_err(|_| Error::InvalidData)?)?;
                let same = current.iter().find(|c| c.id == r.id);
                if same != Some(&r) {
                    r.revision = same
                        .map_or(r.revision, |c| c.revision.max(r.revision))
                        .checked_add(1)
                        .ok_or(Error::Limit)?;
                    r.updated_at = now();
                    *value = serde_json::to_value(r).map_err(|_| Error::InvalidData)?;
                }
            }
            *book = recovered;
            Ok(())
        })
    }
    fn shopping_mutate(
        &self,
        generation: i64,
        operation: &Operation,
        edit: impl FnOnce(&[shopping::Item], &mut storage::Book) -> Result<Vec<shopping::Item>>,
    ) -> Result<ShoppingResult> {
        let mut undo = None;
        let snapshot = self.mutate(generation, operation, |book| {
            let before = Self::shopping(book)?;
            let mut after = edit(&before, book)?;
            for item in &mut after {
                if item.category_id.is_empty() {
                    item.category_id = book.shopping_setup.classify(&item.name);
                }
            }
            book.shopping_setup.validate()?;
            shopping::validate(&after)?;
            undo = Some(shopping::Undo::between(&before, &after));
            book.shopping = after
                .into_iter()
                .map(|i| serde_json::to_value(i).map_err(|_| Error::InvalidData))
                .collect::<Result<_>>()?;
            Ok(())
        })?;
        Ok(ShoppingResult {
            snapshot,
            undo: undo.unwrap(),
        })
    }
    pub fn add_shopping(
        &self,
        generation: i64,
        id: &RecipeId,
        indices: &[u32],
        operation: &Operation,
    ) -> Result<ShoppingResult> {
        self.shopping_mutate(generation, operation, |items, book| {
            let recipe = Self::recipes(book)?
                .into_iter()
                .find(|r| &r.id == id)
                .ok_or(Error::StaleWrite)?;
            shopping::add(items, &recipe, indices)
        })
    }
    pub fn add_shopping_scaled(
        &self,
        generation: i64,
        id: &RecipeId,
        indices: &[u32],
        scale: u32,
        operation: &Operation,
    ) -> Result<ShoppingResult> {
        self.shopping_mutate(generation, operation, |items, book| {
            let recipe = Self::recipes(book)?
                .into_iter()
                .find(|r| &r.id == id)
                .ok_or(Error::StaleWrite)?;
            shopping::add_scaled(items, &recipe, indices, scale)
        })
    }
    pub fn edit_shopping(
        &self,
        generation: i64,
        edit: ShoppingEdit,
        operation: &Operation,
    ) -> Result<ShoppingResult> {
        self.shopping_mutate(generation, operation, |items, book| {
            let mut items = items.to_vec();
            match edit {
                ShoppingEdit::AddManual { text } => items.push(shopping::Item::manual(text)?),
                ShoppingEdit::Edit { id, text } => {
                    let old = items
                        .iter_mut()
                        .find(|i| i.id == id)
                        .ok_or(Error::StaleWrite)?;
                    let mut item = shopping::Item::manual(text)?;
                    item.id = id;
                    item.checked = old.checked;
                    *old = item;
                }
                ShoppingEdit::Check { ids, checked } => {
                    for id in ids {
                        items
                            .iter_mut()
                            .find(|i| i.id == id)
                            .ok_or(Error::StaleWrite)?
                            .checked = checked;
                    }
                }
                ShoppingEdit::Move {
                    id,
                    category_id,
                    before_id,
                } => {
                    let pos = items
                        .iter()
                        .position(|i| i.id == id)
                        .ok_or(Error::StaleWrite)?;
                    book.shopping_setup
                        .remember(&items[pos].name, &category_id)?;
                    let mut item = items.remove(pos);
                    item.category_id = category_id;
                    if let Some(before_id) = before_id {
                        let target = items
                            .iter()
                            .position(|i| {
                                i.id == before_id && i.category_id == item.category_id && !i.checked
                            })
                            .ok_or(Error::StaleWrite)?;
                        if item.checked {
                            return Err(Error::InvalidData);
                        }
                        items.insert(target, item);
                    } else {
                        items.push(item);
                    }
                }
                ShoppingEdit::ReorderItems { category_id, ids } => {
                    if !book.shopping_setup.contains(&category_id) {
                        return Err(Error::InvalidData);
                    }
                    let slots: Vec<_> = items
                        .iter()
                        .enumerate()
                        .filter(|(_, i)| !i.checked && i.category_id == category_id)
                        .map(|(n, _)| n)
                        .collect();
                    let rows = slots.iter().map(|&n| items[n].clone()).collect::<Vec<_>>();
                    if ids.len() != rows.len()
                        || ids.iter().collect::<HashSet<_>>().len() != ids.len()
                    {
                        return Err(Error::InvalidData);
                    }
                    for (slot, id) in slots.into_iter().zip(ids) {
                        items[slot] = rows
                            .iter()
                            .find(|i| i.id == id)
                            .ok_or(Error::InvalidData)?
                            .clone();
                    }
                }
                ShoppingEdit::AddCategory { name } => {
                    book.shopping_setup
                        .categories
                        .push(crate::shopping_categories::Category {
                            id: uuid::Uuid::new_v4().to_string(),
                            name: name.trim().into(),
                        });
                }
                ShoppingEdit::RenameCategory { id, name } => {
                    book.shopping_setup
                        .categories
                        .iter_mut()
                        .find(|c| c.id == id)
                        .ok_or(Error::StaleWrite)?
                        .name = name.trim().into();
                }
                ShoppingEdit::DeleteCategory { id } => {
                    if id == crate::shopping_categories::OTHER || !book.shopping_setup.contains(&id)
                    {
                        return Err(Error::InvalidData);
                    }
                    book.shopping_setup.categories.retain(|c| c.id != id);
                    for item in &mut items {
                        if item.category_id == id {
                            item.category_id = crate::shopping_categories::OTHER.into();
                        }
                    }
                    for category in book.shopping_setup.placements.values_mut() {
                        if *category == id {
                            *category = crate::shopping_categories::OTHER.into();
                        }
                    }
                }
                ShoppingEdit::ReorderCategories { ids } => {
                    let old = &book.shopping_setup.categories;
                    if ids.len() != old.len()
                        || ids.iter().collect::<HashSet<_>>().len() != ids.len()
                    {
                        return Err(Error::InvalidData);
                    }
                    book.shopping_setup.categories = ids
                        .iter()
                        .map(|id| {
                            old.iter()
                                .find(|c| c.id == *id)
                                .cloned()
                                .ok_or(Error::InvalidData)
                        })
                        .collect::<Result<_>>()?;
                }
                ShoppingEdit::Remove { ids } => {
                    if ids.iter().any(|id| !items.iter().any(|i| &i.id == id)) {
                        return Err(Error::StaleWrite);
                    }
                    items.retain(|i| !ids.contains(&i.id));
                }
            }
            Ok(items)
        })
    }
    pub fn undo_shopping(
        &self,
        generation: i64,
        undo: &shopping::Undo,
        operation: &Operation,
    ) -> Result<Snapshot> {
        Ok(self
            .shopping_mutate(generation, operation, |items, _| undo.apply(items))?
            .snapshot)
    }
}
pub fn now() -> String {
    chrono::Utc::now().to_rfc3339_opts(chrono::SecondsFormat::Millis, true)
}
fn put_recipe(book: &mut storage::Book, recipe: Recipe) -> Result<()> {
    recipe.validate()?;
    let id = recipe.id.0.clone();
    let value = serde_json::to_value(recipe).map_err(|_| Error::InvalidData)?;
    if let Some(old) = book.recipes.iter_mut().find(|r| r["id"] == id) {
        *old = value;
    } else {
        book.recipes.push(value);
    }
    book.deleted_recipes.retain(|r| r["id"] != id);
    Ok(())
}
fn merge_recipes(book: &mut storage::Book, incoming: &[Recipe]) -> Result<RestoreReport> {
    let mut report = RestoreReport::default();
    let mut recipes = Service::recipes(book)?;
    let mut positions = recipes
        .iter()
        .enumerate()
        .map(|(i, r)| (r.id.clone(), i))
        .collect::<std::collections::HashMap<_, _>>();
    for r in incoming {
        if let Some(&index) = positions.get(&r.id) {
            let old = &recipes[index];
            let date = |r: &Recipe| {
                chrono::DateTime::parse_from_rfc3339(&r.updated_at).map_err(|_| Error::InvalidData)
            };
            if date(r)? > date(old)? {
                recipes[index] = r.clone();
                put_recipe(book, r.clone())?;
                report.updated += 1;
            } else if date(r)? == date(old)? && r != old {
                report.conflicts.push(r.id.clone());
            } else {
                report.skipped += 1;
            }
        } else {
            positions.insert(r.id.clone(), recipes.len());
            recipes.push(r.clone());
            put_recipe(book, r.clone())?;
            report.added += 1;
        }
    }
    backup::validate_collection(&recipes)?;
    // Keep unchanged schema-1 storage/history bytes intact. A restore only
    // creates revisions for recipes actually added or replaced.
    book.deleted_recipes.retain(|r| {
        !r["id"]
            .as_str()
            .is_some_and(|id| positions.contains_key(&RecipeId(id.into())))
    });
    Ok(report)
}
