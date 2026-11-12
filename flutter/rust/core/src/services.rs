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

mod library;
pub use library::LibraryUndo;

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
#[derive(Debug, Clone)]
pub enum ShoppingEdit {
    AddManual {
        text: String,
    },
    AddManualItems {
        names: Vec<String>,
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
    recipe_cache: Mutex<Option<RecipeCache>>,
}
struct RecipeCache {
    token: (i64, i64),
    stored: storage::Snapshot,
    view: Snapshot,
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
            recipe_cache: Mutex::new(None),
        })
    }
    pub fn editor_units(&self) -> Result<Vec<String>> {
        let mut db = self.session.connection().map_err(db_error)?;
        let mut cache = self.recipe_cache.lock().map_err(|_| Error::Closed)?;
        Self::ensure_recipe_cache(&mut db, &mut cache)?;
        let mut recipes: Vec<_> = cache.as_ref().unwrap().stored.book.recipes.iter().collect();
        recipes.sort_by_key(|r| r["id"].as_str().unwrap());
        // Units are plain text in every supported recipe schema. These bodies
        // already passed canonical validation for this database version.
        Ok(recipes
            .into_iter()
            .flat_map(|r| {
                r["ingredients"]
                    .as_array()
                    .unwrap()
                    .iter()
                    .map(|i| i["unit"].as_str().unwrap().to_owned())
            })
            .collect())
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
        let mut cache = self.recipe_cache.lock().map_err(|_| Error::Closed)?;
        if Self::ensure_recipe_cache(&mut db, &mut cache)? {
            let validated = cache.as_ref().unwrap();
            self.session
                .sync
                .prime_status_read(&db, validated.token, &validated.stored.set_aside)
                .map_err(db_error)?;
        }
        Ok(cache.as_ref().unwrap().view.clone())
    }
    /// Registration and snapshot occur while holding the same lock as commits.
    /// A slow subscriber is disconnected on overflow and must obtain a new snapshot.
    pub fn subscribe(&self) -> Result<Subscription> {
        let mut db = self.session.connection().map_err(db_error)?;
        let mut cache = self.recipe_cache.lock().map_err(|_| Error::Closed)?;
        if Self::ensure_recipe_cache(&mut db, &mut cache)? {
            let validated = cache.as_ref().unwrap();
            self.session
                .sync
                .prime_status_read(&db, validated.token, &validated.stored.set_aside)
                .map_err(db_error)?;
        }
        let snapshot = cache.as_ref().unwrap().view.clone();
        let (tx, receiver) = mpsc::sync_channel(64);
        self.subscribers.lock().map_err(|_| Error::Closed)?.push(tx);
        Ok(Subscription { snapshot, receiver })
    }
    pub fn detail(&self, id: &RecipeId) -> Result<Option<Recipe>> {
        let mut db = self.session.connection().map_err(db_error)?;
        let tx = db.transaction().map_err(|_| Error::Storage)?;
        let recipe = storage::recipe(&tx, id).map_err(db_error)?;
        tx.commit().map_err(|_| Error::Storage)?;
        Ok(recipe)
    }

    fn ensure_recipe_cache(
        db: &mut rusqlite::Connection,
        cache: &mut Option<RecipeCache>,
    ) -> Result<bool> {
        let token = storage::version(db).map_err(db_error)?;
        if cache.as_ref().is_some_and(|c| c.token == token) {
            return Ok(false);
        }
        *cache = None;
        let stored = storage::load(db).map_err(db_error)?;
        let view = Self::snapshot_from(db, &stored)?;
        if storage::version(db).map_err(db_error)? != (stored.generation, token.1) {
            return Err(Error::StaleWrite);
        }
        *cache = Some(RecipeCache {
            token: (stored.generation, token.1),
            stored,
            view,
        });
        Ok(true)
    }

    fn mutate_recipes(
        &self,
        generation: i64,
        operation: &Operation,
        snapshot_before_delete: bool,
        edit: impl FnOnce(&storage::Book) -> Result<(Vec<Recipe>, Vec<RecipeId>)>,
    ) -> Result<Snapshot> {
        operation.check()?;
        let mut db = self.session.connection().map_err(db_error)?;
        let mut cache = self.recipe_cache.lock().map_err(|_| Error::Closed)?;
        Self::ensure_recipe_cache(&mut db, &mut cache)?;
        let current = cache.take().unwrap();
        if generation != current.token.0 {
            return Err(Error::StaleWrite);
        }
        let (changed, deleted) = edit(&current.stored.book)?;
        backup::validate_collection(&changed)?;
        let mut book = current.stored.book.clone();
        let saved_at = now();
        for r in &changed {
            put_recipe(&mut book, r.clone())?;
        }
        let deleted_ids: HashSet<_> = deleted.iter().map(|id| id.0.as_str()).collect();
        book.recipes
            .retain(|r| !r["id"].as_str().is_some_and(|id| deleted_ids.contains(id)));
        book.deleted_recipes
            .retain(|r| !r["id"].as_str().is_some_and(|id| deleted_ids.contains(id)));
        for id in &deleted {
            book.deleted_recipes
                .push(serde_json::json!({"id":id.0,"deletedAt":saved_at}));
        }
        // Project only changed recipes, before committing; never turn a durable
        // write into a failure due to a subsequent whole-collection read.
        let mut reply = current.view.clone();
        let changed_ids: HashSet<_> = changed.iter().map(|r| r.id.0.as_str()).collect();
        reply.summaries.retain(|r| {
            !changed_ids.contains(r.id.0.as_str()) && !deleted_ids.contains(r.id.0.as_str())
        });
        for r in &changed {
            reply.summaries.push(Summary {
                id: r.id.clone(),
                title: r.content.title.clone(),
                description: r.content.description.clone(),
                ingredients: r
                    .content
                    .ingredients
                    .iter()
                    .map(|i| i.name.clone())
                    .collect(),
                tags: r.content.tags.clone(),
                notes: r.content.notes.clone(),
                favorite: r.favorite,
                created_at: r.created_at.clone(),
                updated_at: r.updated_at.clone(),
                servings: r.content.servings.clone(),
                prep_time: r.content.prep_time.clone(),
                cook_time: r.content.cook_time.clone(),
                total_time: r.content.total_time.clone(),
                revision: r.revision,
            });
        }
        reply.summaries.sort_by(|a, b| a.id.0.cmp(&b.id.0));
        operation.commit(|| {
            if snapshot_before_delete {
                rolling_snapshots::before_delete(&mut db).map_err(db_error)?;
            } else {
                rolling_snapshots::attempt(&mut db, "automatic");
            }
            let next = storage::save_validated_changes(
                &mut db,
                current.token,
                &current.stored,
                book.fields(),
                &changed,
                &deleted,
                &saved_at,
            )
            .map_err(db_error)?;
            if !snapshot_before_delete {
                rolling_snapshots::attempt(&mut db, "automatic");
            }
            reply.generation = next;
            reply.has_previous |= current.stored.set_aside.is_empty();
            let change = Change {
                generation: next,
                changed: changed.iter().map(|r| r.id.clone()).collect(),
                deleted,
                shopping_changed: false,
                conflicts_changed: false,
            };
            self.subscribers
                .lock()
                .unwrap()
                .retain(|tx| tx.try_send(change.clone()).is_ok());
            self.session.sync.local_recipe_changed();
            *cache = Some(RecipeCache {
                token: (next, current.token.1),
                stored: storage::Snapshot {
                    generation: next,
                    book,
                    set_aside: current.stored.set_aside.clone(),
                },
                view: reply.clone(),
            });
            Ok(reply)
        })
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
            if reason == "before_library" {
                rolling_snapshots::before_library(&mut db).map_err(db_error)?;
            } else {
                rolling_snapshots::attempt(&mut db, reason);
            }
            let generation = storage::save(&mut db, generation, &book, &now()).map_err(db_error)?;
            // A restore must retain its pre-operation archive until a later snapshot.
            if !matches!(reason, "before_restore" | "before_library") {
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
        self.mutate_recipes(generation, operation, false, |book| {
            let mut recipe = if let Some(base) = base {
                let current = recipe_from_book(book, &base.id)?;
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
            Ok((vec![recipe], vec![]))
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
        self.mutate_recipes(generation, operation, false, |book| {
            let title = recipe::model::normalize_name(&content.title);
            let same_title = |value: &serde_json::Value| {
                value["title"]
                    .as_str()
                    .is_some_and(|name| recipe::model::normalize_name(name) == title)
            };
            let mut imported = Recipe::new(content, &now())?;
            match choice {
                None if book.recipes.iter().any(same_title) => return Err(Error::Conflict),
                Some(DuplicateChoice::Replace { id }) => {
                    let row = book
                        .recipes
                        .iter()
                        .find(|r| r["id"] == id.0 && same_title(r))
                        .ok_or(Error::StaleWrite)?;
                    let old: Recipe =
                        serde_json::from_value(row.clone()).map_err(|_| Error::InvalidData)?;
                    imported.id = old.id;
                    imported.created_at = old.created_at;
                    imported.revision = old.revision.checked_add(1).ok_or(Error::Limit)?;
                }
                _ => (),
            }
            Ok((vec![imported], vec![]))
        })
    }
    pub fn favorite(
        &self,
        generation: i64,
        id: &RecipeId,
        value: bool,
        operation: &Operation,
    ) -> Result<Snapshot> {
        self.mutate_recipes(generation, operation, false, |book| {
            let mut recipe = recipe_from_book(book, id)?;
            recipe.favorite = value;
            // Favorites are metadata: history still advances for sync, while
            // Recently edited continues to describe content edits.
            recipe.revision = recipe.revision.checked_add(1).ok_or(Error::Limit)?;
            Ok((vec![recipe], vec![]))
        })
    }
    pub fn delete(
        &self,
        generation: i64,
        id: &RecipeId,
        operation: &Operation,
    ) -> Result<Snapshot> {
        self.mutate_recipes(generation, operation, false, |book| {
            recipe_from_book(book, id)?;
            Ok((vec![], vec![id.clone()]))
        })
    }
    pub fn delete_many(
        &self,
        generation: i64,
        ids: &[RecipeId],
        operation: &Operation,
    ) -> Result<Snapshot> {
        if ids.is_empty() || ids.len() > recipe::MAX_ITEMS {
            return Err(Error::Validation);
        }
        let unique: HashSet<_> = ids.iter().collect();
        if unique.len() != ids.len() {
            return Err(Error::Validation);
        }
        self.mutate_recipes(generation, operation, true, |book| {
            let existing: HashSet<_> = book
                .recipes
                .iter()
                .filter_map(|r| r["id"].as_str())
                .collect();
            if ids.iter().any(|id| !existing.contains(id.0.as_str())) {
                return Err(Error::StaleWrite);
            }
            Ok((vec![], ids.to_vec()))
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
        edit: impl FnOnce(
            &[shopping::Item],
            &storage::Book,
            &mut crate::shopping_categories::Setup,
        ) -> Result<Vec<shopping::Item>>,
    ) -> Result<ShoppingResult> {
        operation.check()?;
        let mut db = self.session.connection().map_err(db_error)?;
        let mut cache = self.recipe_cache.lock().map_err(|_| Error::Closed)?;
        Self::ensure_recipe_cache(&mut db, &mut cache)?;
        let current = cache.as_mut().unwrap();
        if generation != current.token.0 {
            return Err(Error::StaleWrite);
        }

        let mut setup = current.stored.book.shopping_setup.clone();
        let before = &current.view.shopping;
        let mut after = edit(before, &current.stored.book, &mut setup)?;
        for item in &mut after {
            if item.category_id.is_empty() {
                item.category_id = setup.classify(&item.name);
            }
        }
        setup.validate()?;
        shopping::validate(&after)?;
        let undo = shopping::Undo::between(before, &after);
        let rows: Vec<_> = after
            .iter()
            .map(serde_json::to_value)
            .collect::<std::result::Result<_, _>>()
            .map_err(|_| Error::InvalidData)?;
        // An undo can restore a reference to a category that has since been
        // removed. Keep the usual read projection for those historical rows.
        for item in &mut after {
            if !setup.contains(&item.category_id) {
                item.category_id = crate::shopping_categories::OTHER.into();
            }
        }
        let changed =
            rows != current.stored.book.shopping || setup != current.stored.book.shopping_setup;
        operation.commit(|| {
            rolling_snapshots::attempt(&mut db, "automatic");
            let next = storage::save_validated_changes(
                &mut db,
                current.token,
                &current.stored,
                current.stored.book.fields().with_shopping(&rows, &setup),
                &[],
                &[],
                &now(),
            )
            .map_err(db_error)?;
            rolling_snapshots::attempt(&mut db, "automatic");
            current.view.generation = next;
            current.view.has_previous |= current.stored.set_aside.is_empty();
            current.view.shopping = after;
            current.view.shopping_categories = setup.categories.clone();
            current.stored.book.shopping = rows;
            current.stored.book.shopping_setup = setup;
            current.stored.generation = next;
            current.token.0 = next;
            let change = Change {
                generation: next,
                changed: vec![],
                deleted: vec![],
                shopping_changed: changed,
                conflicts_changed: false,
            };
            self.subscribers
                .lock()
                .unwrap()
                .retain(|tx| tx.try_send(change.clone()).is_ok());
            Ok(ShoppingResult {
                snapshot: current.view.clone(),
                undo,
            })
        })
    }
    pub fn add_shopping(
        &self,
        generation: i64,
        id: &RecipeId,
        indices: &[u32],
        operation: &Operation,
    ) -> Result<ShoppingResult> {
        self.shopping_mutate(generation, operation, |items, book, _| {
            let recipe = recipe_from_book(book, id)?;
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
        self.shopping_mutate(generation, operation, |items, book, _| {
            let recipe = recipe_from_book(book, id)?;
            shopping::add_scaled(items, &recipe, indices, scale)
        })
    }
    pub fn edit_shopping(
        &self,
        generation: i64,
        edit: ShoppingEdit,
        operation: &Operation,
    ) -> Result<ShoppingResult> {
        self.shopping_mutate(generation, operation, |items, _, setup| {
            let mut items = items.to_vec();
            match edit {
                ShoppingEdit::AddManual { text } => items.push(shopping::Item::manual(text)?),
                ShoppingEdit::AddManualItems { names } => {
                    shopping::add_idea_items(&mut items, &names)?;
                }
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
                    setup.remember(&items[pos].name, &category_id)?;
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
                    if !setup.contains(&category_id) {
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
                    setup.categories.push(crate::shopping_categories::Category {
                        id: uuid::Uuid::new_v4().to_string(),
                        name: name.trim().into(),
                    });
                }
                ShoppingEdit::RenameCategory { id, name } => {
                    setup
                        .categories
                        .iter_mut()
                        .find(|c| c.id == id)
                        .ok_or(Error::StaleWrite)?
                        .name = name.trim().into();
                }
                ShoppingEdit::DeleteCategory { id } => {
                    if id == crate::shopping_categories::OTHER || !setup.contains(&id) {
                        return Err(Error::InvalidData);
                    }
                    setup.categories.retain(|c| c.id != id);
                    for item in &mut items {
                        if item.category_id == id {
                            item.category_id = crate::shopping_categories::OTHER.into();
                        }
                    }
                    for category in setup.placements.values_mut() {
                        if *category == id {
                            *category = crate::shopping_categories::OTHER.into();
                        }
                    }
                }
                ShoppingEdit::ReorderCategories { ids } => {
                    let old = &setup.categories;
                    if ids.len() != old.len()
                        || ids.iter().collect::<HashSet<_>>().len() != ids.len()
                    {
                        return Err(Error::InvalidData);
                    }
                    setup.categories = ids
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
            .shopping_mutate(generation, operation, |items, _, _| undo.apply(items))?
            .snapshot)
    }
}
pub fn now() -> String {
    chrono::Utc::now().to_rfc3339_opts(chrono::SecondsFormat::Millis, true)
}
fn recipe_from_book(book: &storage::Book, id: &RecipeId) -> Result<Recipe> {
    let value = book
        .recipes
        .iter()
        .find(|r| r["id"] == id.0)
        .ok_or(Error::StaleWrite)?;
    Recipe::from_json(&serde_json::to_vec(value).map_err(|_| Error::InvalidData)?)
        .map_err(Into::into)
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
