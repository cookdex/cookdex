//! An optional native-owned UI-only ADPF session. All pointer use, including
//! lifecycle cleanup from Java, is serialized. No borrowed JNI objects survive.
use std::ffi::{c_char, c_int, c_void};
use std::sync::{Mutex, OnceLock};

type Manager = unsafe extern "C" fn() -> *mut c_void;
type Create = unsafe extern "C" fn(*mut c_void, *const i32, usize, i64) -> *mut c_void;
type Duration = unsafe extern "C" fn(*mut c_void, i64) -> c_int;
type Close = unsafe extern "C" fn(*mut c_void);
type Notify = unsafe extern "C" fn(*mut c_void, bool, bool, *const c_char) -> c_int;
struct Api {
    manager: Manager,
    create: Create,
    report: Duration,
    target: Duration,
    close: Close,
    increase: Option<Notify>,
    reset: Option<Notify>,
}

#[link(name = "dl")]
unsafe extern "C" {
    fn dlopen(name: *const c_char, flags: c_int) -> *mut c_void;
    fn dlsym(handle: *mut c_void, name: *const c_char) -> *mut c_void;
    fn dlclose(handle: *mut c_void) -> c_int;
    fn gettid() -> c_int;
}

fn api() -> Option<&'static Api> {
    static API: OnceLock<Option<Api>> = OnceLock::new();
    API.get_or_init(|| unsafe {
        let library = dlopen(c"libandroid.so".as_ptr(), 2);
        if library.is_null() {
            return None;
        }
        let manager = dlsym(library, c"APerformanceHint_getManager".as_ptr());
        let create = dlsym(library, c"APerformanceHint_createSession".as_ptr());
        let report = dlsym(
            library,
            c"APerformanceHint_reportActualWorkDuration".as_ptr(),
        );
        let target = dlsym(
            library,
            c"APerformanceHint_updateTargetWorkDuration".as_ptr(),
        );
        let close = dlsym(library, c"APerformanceHint_closeSession".as_ptr());
        if [manager, create, report, target, close]
            .iter()
            .any(|p| p.is_null())
        {
            dlclose(library);
            return None;
        }
        let increase = dlsym(library, c"APerformanceHint_notifyWorkloadIncrease".as_ptr());
        let reset = dlsym(library, c"APerformanceHint_notifyWorkloadReset".as_ptr());
        // Keep the library loaded while these process-lifetime pointers exist.
        Some(Api {
            manager: std::mem::transmute::<*mut c_void, Manager>(manager),
            create: std::mem::transmute::<*mut c_void, Create>(create),
            report: std::mem::transmute::<*mut c_void, Duration>(report),
            target: std::mem::transmute::<*mut c_void, Duration>(target),
            close: std::mem::transmute::<*mut c_void, Close>(close),
            increase: if increase.is_null() {
                None
            } else {
                Some(std::mem::transmute::<*mut c_void, Notify>(increase))
            },
            reset: if reset.is_null() {
                None
            } else {
                Some(std::mem::transmute::<*mut c_void, Notify>(reset))
            },
        })
    })
    .as_ref()
}

struct Live {
    // Only dereferenced under STATE's mutex; no Java owner can close it.
    pointer: usize,
    token: i64,
    target: i64,
}
struct State {
    resumed: bool,
    next: i64,
    live: Option<Live>,
}
static STATE: Mutex<State> = Mutex::new(State {
    resumed: false,
    next: 1,
    live: None,
});

fn close(state: &mut State, api: &Api) {
    if let Some(live) = state.live.take() {
        unsafe {
            let pointer = live.pointer as *mut c_void;
            if let Some(reset) = api.reset {
                reset(pointer, true, false, c"cookdex.ui.settled".as_ptr());
            }
            (api.close)(pointer);
        }
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn cookdex_ui_hint_open(ui_tid: i32, target: i64) -> i64 {
    std::panic::catch_unwind(|| {
        if target <= 0 || ui_tid <= 0 || ui_tid != unsafe { gettid() } {
            return 0;
        }
        let Some(api) = api() else {
            return 0;
        };
        let Ok(mut state) = STATE.lock() else {
            return 0;
        };
        if !state.resumed {
            return 0;
        }
        close(&mut state, api);
        unsafe {
            let manager = (api.manager)();
            if manager.is_null() {
                return 0;
            }
            let pointer = (api.create)(manager, &ui_tid, 1, target);
            if pointer.is_null() {
                return 0;
            }
            let token = state.next;
            state.next = state.next.checked_add(1).unwrap_or(1);
            state.live = Some(Live {
                pointer: pointer as usize,
                token,
                target,
            });
            token
        }
    })
    .unwrap_or(0)
}

#[unsafe(no_mangle)]
pub extern "C" fn cookdex_ui_hint_report(token: i64, work: i64, target: i64) -> c_int {
    std::panic::catch_unwind(|| {
        if work <= 0 || target <= 0 {
            return 22;
        }
        let Some(api) = api() else {
            return 38;
        };
        let Ok(mut state) = STATE.lock() else {
            return 38;
        };
        let Some(live) = state.live.as_mut().filter(|s| s.token == token) else {
            return 22;
        };
        unsafe {
            let pointer = live.pointer as *mut c_void;
            if target != live.target {
                let result = (api.target)(pointer, target);
                if result != 0 {
                    return result;
                }
                live.target = target;
            }
            (api.report)(pointer, work)
        }
    })
    .unwrap_or(38)
}

#[unsafe(no_mangle)]
pub extern "C" fn cookdex_ui_hint_increase(token: i64) -> c_int {
    std::panic::catch_unwind(|| {
        let Some(api) = api() else {
            return 38;
        };
        let Ok(state) = STATE.lock() else {
            return 38;
        };
        let Some(live) = state.live.as_ref().filter(|s| s.token == token) else {
            return 22;
        };
        let Some(increase) = api.increase else {
            return 38;
        };
        unsafe {
            increase(
                live.pointer as *mut c_void,
                true,
                false,
                c"cookdex.ui.start".as_ptr(),
            )
        }
    })
    .unwrap_or(38)
}

#[unsafe(no_mangle)]
pub extern "C" fn cookdex_ui_hint_close(token: i64) {
    let _ = std::panic::catch_unwind(|| {
        let Some(api) = api() else {
            return;
        };
        if let Ok(mut state) = STATE.lock() {
            if state.live.as_ref().is_some_and(|s| s.token == token) {
                close(&mut state, api);
            }
        }
    });
}

#[unsafe(no_mangle)]
pub extern "system" fn Java_com_sylph_cookdex_FramePerformanceHints_00024Companion_setUiResumedNative(
    _env: *mut c_void,
    _companion: *mut c_void,
    resumed: u8,
) {
    let _ = std::panic::catch_unwind(|| {
        if let Ok(mut state) = STATE.lock() {
            state.resumed = resumed != 0;
            if !state.resumed {
                if let Some(api) = api() {
                    close(&mut state, api);
                }
            }
        }
    });
}
