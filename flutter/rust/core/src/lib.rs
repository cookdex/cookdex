//! Flutter-owned foundation. No Tauri, platform context, or default data lookup.
pub mod adapters;
pub mod recipe;
// Copied transport entry points are exercised by tests; exposed to services in C3/C9.
pub mod backup;
#[allow(dead_code)]
mod lan_sync;
pub mod provider;
pub mod services;
pub mod session;
pub mod shopping;
pub mod shopping_categories;
pub mod storage;
pub mod sync_engine;
pub mod sync_store;

pub mod rolling_snapshots;
