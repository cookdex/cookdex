pub mod api;
mod convert;
// JNI entry point for Auto Backup when the Flutter engine is not running.
#[cfg(target_os = "android")]
#[unsafe(no_mangle)]
pub extern "system" fn Java_com_sylph_cookdex_PhoneBackupAgent_writeLibrary(
    _env: *mut std::ffi::c_void,
    _agent: *mut std::ffi::c_void,
    database_fd: i32,
    output_fd: i32,
) -> u8 {
    std::panic::catch_unwind(|| {
        database_fd >= 0
            && output_fd >= 0
            && cookdex_core::sync_store::phone_backup::write_to_files(database_fd, output_fd)
                .is_ok()
    })
    .unwrap_or(false) as u8
}
#[cfg(target_os = "android")]
#[unsafe(no_mangle)]
pub extern "system" fn Java_com_sylph_cookdex_PhoneBackupAgent_restoreLibrary(
    _env: *mut std::ffi::c_void,
    _agent: *mut std::ffi::c_void,
    input_fd: i32,
    database_fd: i32,
) -> u8 {
    std::panic::catch_unwind(|| {
        input_fd >= 0
            && database_fd >= 0
            && cookdex_core::sync_store::phone_backup::restore_to_file(input_fd, database_fd)
                .is_ok()
    })
    .unwrap_or(false) as u8
}
mod frb_generated; /* AUTO INJECTED BY flutter_rust_bridge. This line may not be accurate, and you can change it according to your needs. */
