//! Platform contracts only. Native implementations arrive with services/settings.
//! Implementations must use newly entered Flutter settings, never old Tauri stores.
use std::path::PathBuf;

pub trait AppPaths {
    /// Absolute app-private root (or a disposable test root), supplied explicitly.
    fn private_root(&self) -> Result<PathBuf, String>;
}

/// Secret values are internal to services; never expose them in settings DTOs.
pub trait SecretStore: Send + Sync {
    fn read_key(&self) -> Result<Option<String>, String>;
    fn write_key(&self, key: &str) -> Result<(), String>;
    fn remove_key(&self) -> Result<(), String>;
}

pub trait TrustCertificates: Send + Sync {
    /// DER-encoded platform trust anchors; no Tao/ndk_context global assumptions.
    fn certificates(&self) -> Result<Vec<Vec<u8>>, String>;
}

pub enum SettingsLink {
    ApiKey,
    Pricing,
}

pub trait ExternalLinks: Send + Sync {
    fn open(&self, link: SettingsLink) -> Result<(), String>;
}
