//! Optional public API36 workload hints on the existing Java-owned session.
//! Resolve symbols at runtime so API31-35 keep ordinary frame hints unchanged.
use std::ffi::{c_char, c_int, c_void};
use std::sync::OnceLock;

type Borrow = unsafe extern "C" fn(*mut c_void, *mut c_void) -> *mut c_void;
type Notify = unsafe extern "C" fn(*mut c_void, bool, bool, *const c_char) -> c_int;
struct Functions {
    borrow: Borrow,
    increase: Notify,
    reset: Notify,
}

#[link(name = "dl")]
unsafe extern "C" {
    fn dlopen(name: *const c_char, flags: c_int) -> *mut c_void;
    fn dlsym(handle: *mut c_void, name: *const c_char) -> *mut c_void;
    fn dlclose(handle: *mut c_void) -> c_int;
}

fn functions() -> Option<&'static Functions> {
    static FUNCTIONS: OnceLock<Option<Functions>> = OnceLock::new();
    FUNCTIONS
        .get_or_init(|| unsafe {
            let library = dlopen(c"libandroid.so".as_ptr(), 2); // RTLD_NOW
            if library.is_null() {
                return None;
            }
            let borrow = dlsym(library, c"APerformanceHint_borrowSessionFromJava".as_ptr());
            let increase = dlsym(library, c"APerformanceHint_notifyWorkloadIncrease".as_ptr());
            let reset = dlsym(library, c"APerformanceHint_notifyWorkloadReset".as_ptr());
            if borrow.is_null() || increase.is_null() || reset.is_null() {
                dlclose(library);
                return None;
            }
            // One process-lifetime library reference keeps all three pointers valid.
            Some(Functions {
                borrow: std::mem::transmute::<*mut c_void, Borrow>(borrow),
                increase: std::mem::transmute::<*mut c_void, Notify>(increase),
                reset: std::mem::transmute::<*mut c_void, Notify>(reset),
            })
        })
        .as_ref()
}

#[unsafe(no_mangle)]
pub extern "system" fn Java_com_sylph_cookdex_FramePerformanceHints_00024Companion_notifyWorkloadNative(
    env: *mut c_void,
    _companion: *mut c_void,
    java_session: *mut c_void,
    increased: u8,
) -> c_int {
    std::panic::catch_unwind(|| {
        if env.is_null() || java_session.is_null() {
            return 22;
        }
        let Some(api) = functions() else {
            return 38;
        };
        // The JNI argument holds the Java owner alive for this whole call.
        // Borrow only here, use immediately, never store or close the pointer.
        unsafe {
            let session = (api.borrow)(env, java_session);
            if session.is_null() {
                return 22;
            }
            if increased != 0 {
                (api.increase)(session, true, false, c"cookdex.scroll.start".as_ptr())
            } else {
                (api.reset)(session, true, false, c"cookdex.scroll.settled".as_ptr())
            }
        }
    })
    .unwrap_or(38)
}
