//! UI-independent sync host. Android's activity (or a future foreground service)
//! supplies host availability; Windows supplies availability for the app lifetime.
use crate::lan_sync;
use serde_json::Value;
use std::sync::{Arc, Condvar, Mutex};
use std::time::{Duration, Instant};

#[derive(Default)]
struct Schedule {
    active: bool,
    pairing: bool,
    stopped: bool,
    due: Option<Instant>,
}
impl Schedule {
    fn resume(&mut self, now: Instant) {
        self.active = true;
        self.due = Some(now);
    }
    fn local_change(&mut self, now: Instant) {
        self.due = Some(now + Duration::from_millis(1500));
    }
    fn finish(&mut self, now: Instant) {
        if self.due.is_none() {
            self.due = Some(now + Duration::from_secs(120));
        }
    }
    fn retry_by(&mut self, retry: Option<Instant>) {
        if let Some(retry) = retry {
            self.due = Some(self.due.map_or(retry, |due| due.min(retry)));
        }
    }
    fn delay(&self, now: Instant) -> Option<Duration> {
        if !self.active || self.pairing {
            return None;
        }
        self.due.map(|due| due.saturating_duration_since(now))
    }
}

pub struct Engine {
    transport: lan_sync::Service,
    state: Arc<(Mutex<Schedule>, Condvar)>,
    worker: Mutex<Option<std::thread::JoinHandle<()>>>,
}
impl Engine {
    pub fn new(transport: lan_sync::Service) -> Self {
        let state = Arc::new((Mutex::new(Schedule::default()), Condvar::new()));
        let (shared, service) = (state.clone(), transport.clone());
        let worker = std::thread::spawn(move || {
            let (mutex, wake) = &*shared;
            let mut state = mutex.lock().unwrap();
            loop {
                if state.stopped {
                    break;
                }
                match state.delay(Instant::now()) {
                    Some(delay) if delay.is_zero() => {
                        // Consume only the current request. Edits during networking
                        // install another deadline and survive this exchange.
                        state.due = None;
                        drop(state);
                        if let Err(error) = service.sync_with_mode(false) {
                            service.report_engine_error(error);
                        }
                        state = mutex.lock().unwrap();
                        state.finish(Instant::now());
                        state.retry_by(service.next_retry());
                    }
                    Some(delay) => state = wake.wait_timeout(state, delay).unwrap().0,
                    None => state = wake.wait(state).unwrap(),
                }
            }
        });
        Self {
            transport,
            state,
            worker: Mutex::new(Some(worker)),
        }
    }
    pub fn on_change(&self, callback: Arc<dyn Fn(i64, Vec<String>) + Send + Sync>) {
        self.transport.on_change(callback);
    }
    pub fn host_active(&self, active: bool) -> Result<(), String> {
        self.transport.foreground(active)?;
        let enabled = self.transport.status()?["enabled"]
            .as_bool()
            .unwrap_or(false);
        let mut state = self.state.0.lock().unwrap();
        let available = active && enabled;
        if available && !state.active {
            state.resume(Instant::now());
        }
        state.active = available;
        self.state.1.notify_all();
        Ok(())
    }
    pub fn configure(&self, enabled: bool, name: String) -> Result<(), String> {
        self.transport.configure(enabled, name)?;
        let active = self.transport.status()?["active"]
            .as_bool()
            .unwrap_or(false);
        let mut state = self.state.0.lock().unwrap();
        if active && !state.active {
            state.resume(Instant::now());
        }
        state.active = active;
        self.state.1.notify_all();
        Ok(())
    }
    pub fn pairing(&self, pairing: bool) {
        let mut state = self.state.0.lock().unwrap();
        state.pairing = pairing;
        if !pairing {
            state.due = Some(Instant::now());
        }
        self.state.1.notify_all();
    }
    pub fn dismiss_pairing_notice(&self) -> Result<(), String> {
        self.transport.dismiss_pairing_notice()
    }
    pub fn local_recipe_changed(&self) {
        self.state.0.lock().unwrap().local_change(Instant::now());
        self.state.1.notify_all();
    }
    pub fn status(&self) -> Result<Value, String> {
        self.transport.status()
    }
    pub fn invitation(&self, address: String) -> Result<String, String> {
        self.transport.invitation(address)
    }
    pub fn pair(&self, code: String) -> Result<(), String> {
        self.transport.pair(code)
    }
    pub fn forget(&self, id: &str) -> Result<(), String> {
        self.transport.forget(id)
    }
    pub fn manual(&self) -> Result<(), String> {
        // Transport serializes manual, automatic and pairing exchanges.
        let result = self.transport.sync_prepared(true, || {
            // Consume pending work only once this exchange owns the transport.
            // Any edit after this point installs a deadline we must preserve,
            // even when a slow manual transfer outlasts its debounce.
            self.state.0.lock().unwrap().due = None;
        });
        let mut state = self.state.0.lock().unwrap();
        state.finish(Instant::now());
        state.retry_by(self.transport.next_retry());
        self.state.1.notify_all();
        drop(state);
        result?;
        Ok(())
    }
}
impl Drop for Engine {
    fn drop(&mut self) {
        self.state.0.lock().unwrap().stopped = true;
        self.state.1.notify_all();
        self.transport.shutdown();
        if let Some(worker) = self.worker.lock().unwrap().take() {
            let _ = worker.join();
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn retry_deadline_wakes_before_idle_but_preserves_earlier_edit() {
        let now = Instant::now();
        let mut s = Schedule::default();
        s.resume(now);
        s.due = None;
        s.finish(now);
        s.retry_by(Some(now + Duration::from_secs(60)));
        assert_eq!(s.delay(now), Some(Duration::from_secs(60)));
        s.local_change(now);
        s.retry_by(Some(now + Duration::from_secs(60)));
        assert_eq!(s.delay(now), Some(Duration::from_millis(1500)));
    }
    #[test]
    fn start_resume_and_idle_exchange_timing_matches_retained_schedule() {
        let now = Instant::now();
        let mut s = Schedule::default();
        s.resume(now);
        assert_eq!(s.delay(now), Some(Duration::ZERO));
        s.due = None;
        s.finish(now);
        assert_eq!(s.delay(now), Some(Duration::from_secs(120)));
        s.active = false;
        assert_eq!(s.delay(now + Duration::from_secs(500)), None);
        s.resume(now + Duration::from_secs(500));
        assert_eq!(
            s.delay(now + Duration::from_secs(500)),
            Some(Duration::ZERO)
        );
    }
    #[test]
    fn local_edits_debounce_and_restart_idle_without_refresh_ping_pong() {
        let now = Instant::now();
        let mut s = Schedule::default();
        s.resume(now);
        s.due = None;
        s.finish(now);
        s.local_change(now);
        s.local_change(now + Duration::from_secs(1));
        assert_eq!(
            s.delay(now + Duration::from_millis(2499)),
            Some(Duration::from_millis(1))
        );
        s.due = None;
        s.finish(now + Duration::from_millis(2500));
        assert_eq!(
            s.delay(now + Duration::from_millis(2500)),
            Some(Duration::from_secs(120))
        );
    }
    #[test]
    fn disabled_or_unavailable_host_stops_and_resume_sends_pending_edits() {
        let now = Instant::now();
        let mut s = Schedule::default();
        s.local_change(now);
        assert_eq!(s.delay(now + Duration::from_secs(300)), None);
        s.resume(now + Duration::from_secs(300));
        assert_eq!(
            s.delay(now + Duration::from_secs(300)),
            Some(Duration::ZERO)
        );
    }
    #[test]
    fn pairing_pauses_automatic_work_until_ui_closes() {
        let now = Instant::now();
        let mut s = Schedule::default();
        s.resume(now);
        s.pairing = true;
        assert_eq!(s.delay(now + Duration::from_secs(30)), None);
        s.pairing = false;
        assert_eq!(s.delay(now + Duration::from_secs(30)), Some(Duration::ZERO));
    }
    #[test]
    fn local_change_during_exchange_survives_completion() {
        let now = Instant::now();
        let mut s = Schedule::default();
        s.resume(now);
        s.due = None;
        s.local_change(now);
        s.finish(now + Duration::from_secs(1));
        assert_eq!(
            s.delay(now + Duration::from_secs(1)),
            Some(Duration::from_millis(500))
        );
    }
    #[test]
    fn slow_manual_exchange_does_not_replace_an_expired_local_edit_deadline() {
        let now = Instant::now();
        let mut s = Schedule::default();
        s.resume(now);
        s.due = None; // manual consumes pending work at transport acquisition
        s.local_change(now + Duration::from_secs(1));
        s.finish(now + Duration::from_secs(20));
        assert_eq!(s.delay(now + Duration::from_secs(20)), Some(Duration::ZERO));
    }
    #[test]
    fn resume_debounce_pairing_pause_and_pending_edits_use_monotonic_time() {
        let now = Instant::now();
        let mut s = Schedule::default();
        s.resume(now);
        assert_eq!(s.delay(now), Some(Duration::ZERO));
        s.local_change(now);
        s.local_change(now + Duration::from_secs(1));
        assert_eq!(s.delay(now), Some(Duration::from_millis(2500)));
        s.pairing = true;
        assert_eq!(s.delay(now + Duration::from_secs(9)), None);
        s.pairing = false;
        assert_eq!(s.delay(now + Duration::from_secs(9)), Some(Duration::ZERO));
        s.active = false;
        assert_eq!(s.delay(now), None);
        s.resume(now);
        assert_eq!(s.delay(now), Some(Duration::ZERO));
    }
}
