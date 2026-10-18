//! Host-availability-gated LAN transport: Noise NNpsk0 authenticated with an out-of-band,
//! one-use random pairing secret. No recipe or secret is sent in cleartext.
use crate::{storage, sync_store};
use base64::{Engine, engine::general_purpose::URL_SAFE_NO_PAD as B64};
use rusqlite::Connection;
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};
use sha2::{Digest, Sha256};
use std::{
    collections::{BTreeMap, BTreeSet},
    io::{Read, Write},
    net::{IpAddr, Ipv4Addr, Shutdown, SocketAddr, TcpListener, TcpStream, UdpSocket},
    sync::{
        Arc, Mutex,
        atomic::{AtomicBool, AtomicU16, AtomicUsize, Ordering},
    },
    time::{Duration, Instant, SystemTime, UNIX_EPOCH},
};
use uuid::Uuid;
pub const PORT: u16 = if cfg!(feature = "production-sync") {
    47831
} else {
    47832
};
const DOMAIN: &str = if cfg!(feature = "production-sync") {
    "cookdex-flutter-production/1"
} else {
    "cookdex-flutter-development/1"
};
const MAX: usize = 96 * 1024 * 1024;
const VERSION: u32 = 4;
const VERSION_ERROR: &str = "Update cookdex on the other device to keep syncing.";
const NEWER_VERSION_ERROR: &str = "This device needs an update to keep syncing.";
const AUTH_TIMEOUT: Duration = Duration::from_secs(10);
const COOLDOWN: Duration = Duration::from_secs(2);
const PATTERN: &str = "Noise_NNpsk0_25519_ChaChaPoly_BLAKE2s";
fn err(e: impl std::fmt::Display) -> String {
    e.to_string()
}
fn now() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs()
}
fn lock<T>(m: &Mutex<T>) -> Result<std::sync::MutexGuard<'_, T>, String> {
    m.lock().map_err(|_| "Sync state unavailable".into())
}
#[derive(Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct Peer {
    id: String,
    name: String,
    address: String,
    pair: String,
    key: String,
    #[serde(default)]
    last_sync: Option<u64>,
    #[serde(default)]
    acknowledged: Option<String>,
}
#[derive(Clone, Serialize, Deserialize)]
struct Config {
    #[serde(default)]
    protocol: u32,
    #[serde(default)]
    re_pair_required: bool,
    enabled: bool,
    name: String,
    peers: Vec<Peer>,
    #[serde(default)]
    staged: Vec<StagedPeer>,
}
#[derive(Clone, Serialize, Deserialize)]
struct StagedPeer {
    peer: Peer,
}
impl Default for Config {
    fn default() -> Self {
        Self {
            protocol: VERSION,
            re_pair_required: false,
            enabled: false,
            name: if cfg!(target_os = "android") {
                "Android device"
            } else {
                "Windows PC"
            }
            .into(),
            peers: vec![],
            staged: vec![],
        }
    }
}
#[derive(Clone, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
struct Invitation {
    domain: String,
    version: u32,
    id: String,
    name: String,
    address: String,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    alternatives: Vec<String>,
    pair: String,
    key: String,
}
struct Pending {
    invite: Invitation,
    expires: Instant,
}
struct Runtime {
    config: Config,
    pending: Option<Pending>,
    pairing_epoch: u64,
    started: bool,
    error: Option<String>,
    retries: BTreeMap<String, Retry>,
    reports: BTreeMap<String, Value>,
    inbound_interruptions: u32,
}
#[derive(Default)]
struct Admission {
    sources: BTreeMap<IpAddr, Source>,
}
struct Source {
    busy: bool,
    retry: Instant,
}
impl Admission {
    fn acquire(&mut self, ip: IpAddr, at: Instant) -> bool {
        self.sources
            .retain(|_, source| source.busy || source.retry > at);
        if self.sources.contains_key(&ip) || self.sources.len() >= 128 {
            return false;
        }
        self.sources.insert(
            ip,
            Source {
                busy: true,
                retry: at,
            },
        );
        true
    }
    fn release(&mut self, ip: IpAddr, failed: bool, at: Instant) {
        if failed {
            self.sources.insert(
                ip,
                Source {
                    busy: false,
                    retry: at + COOLDOWN,
                },
            );
        } else {
            self.sources.remove(&ip);
        }
    }
}
struct AdmissionGuard {
    admission: Arc<Mutex<Admission>>,
    ip: IpAddr,
    authenticated: bool,
}
impl AdmissionGuard {
    fn authenticated(&mut self) {
        if !self.authenticated {
            if let Ok(mut admission) = self.admission.lock() {
                admission.release(self.ip, false, Instant::now());
            }
            self.authenticated = true;
        }
    }
}
impl Drop for AdmissionGuard {
    fn drop(&mut self) {
        if !self.authenticated {
            if let Ok(mut admission) = self.admission.lock() {
                admission.release(self.ip, true, Instant::now());
            }
        }
    }
}
struct Retry {
    failures: u32,
    next: Instant,
}
impl Runtime {
    fn retry_after(&self, id: &str, force: bool, at: Instant) -> Option<u64> {
        if force {
            return None;
        }
        self.retries.get(id).and_then(|retry| {
            retry
                .next
                .checked_duration_since(at)
                .filter(|d| !d.is_zero())
                .map(|d| d.as_secs() + u64::from(d.subsec_nanos() > 0))
        })
    }
    fn record_result(&mut self, id: &str, result: &Result<(), String>, at: Instant) {
        if result.as_ref().is_err_and(|e| {
            e.starts_with("Device unavailable.")
                || transient_transfer(e)
                || e.contains(sync_store::RECIPE_ERROR)
                || e.contains(sync_store::SET_ASIDE_ERROR)
                || version_error(e)
        }) {
            let failures = self
                .retries
                .get(id)
                .map_or(1, |retry| retry.failures.saturating_add(1));
            let seconds = match failures {
                1 => 60,
                2 => 120,
                3 => 240,
                _ => 300,
            };
            self.retries.insert(
                id.into(),
                Retry {
                    failures,
                    next: at + Duration::from_secs(seconds),
                },
            );
        } else {
            self.retries.remove(id);
        }
    }
}
#[derive(Clone)]
pub struct Service {
    db: Arc<Mutex<Connection>>,
    runtime: Arc<Mutex<Runtime>>,
    active: Arc<AtomicBool>,
    inbound: Arc<AtomicUsize>,
    admission: Arc<Mutex<Admission>>,
    stopped: Arc<AtomicBool>,
    listener_port: Arc<AtomicU16>,
    workers: Arc<Mutex<Vec<std::thread::JoinHandle<()>>>>,
    receivers: Arc<Mutex<Vec<(TcpStream, std::thread::JoinHandle<()>)>>>,
    id: String,
    port: u16,
    host_active: Arc<AtomicBool>,
    outgoing: Arc<Mutex<()>>,
    on_change: Arc<Mutex<Option<Arc<dyn Fn(i64, Vec<String>) + Send + Sync>>>>,
}
#[derive(Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
struct Inventory {
    #[serde(default = "default_port")]
    port: u16,
    version: u32,
    id: String,
    name: String,
    summary: Summary,
}
#[derive(Serialize, Deserialize, PartialEq)]
#[serde(deny_unknown_fields)]
struct Summary {
    count: usize,
    digest: String,
}
fn summary(manifest: &sync_store::Manifest) -> Result<Summary, String> {
    let mut identities: Vec<_> = manifest.events.iter().map(|e| (&e.id, &e.digest)).collect();
    identities.sort_unstable();
    Ok(Summary {
        count: identities.len(),
        digest: format!(
            "{:x}",
            Sha256::digest(serde_json::to_vec(&identities).map_err(err)?)
        ),
    })
}
// History IDs are immutable and never reused; compaction preserves IDs. Record
// only the union of the two exchange snapshots, never the current database:
// a concurrent edit must remain pending even when it precedes the final receipt.
fn identity_set(ids: impl IntoIterator<Item = String>) -> String {
    let ids: BTreeSet<String> = ids.into_iter().collect();
    format!(
        "{:x}",
        Sha256::digest(serde_json::to_vec(&(VERSION, ids)).expect("string set"))
    )
}
fn acknowledged_union(local: &sync_store::Manifest, remote: &sync_store::Manifest) -> String {
    identity_set(
        local
            .events
            .iter()
            .chain(&remote.events)
            .map(|e| e.id.clone()),
    )
}
fn history_identity(conn: &Connection) -> Result<String, String> {
    let mut stmt = conn
        .prepare("SELECT id FROM history ORDER BY id")
        .map_err(err)?;
    let rows = stmt
        .query_map([], |row| row.get::<_, String>(0))
        .map_err(err)?;
    Ok(identity_set(
        rows.collect::<Result<Vec<_>, _>>().map_err(err)?,
    ))
}
#[derive(Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
struct Receipt {
    version: u32,
}
#[derive(Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
struct Identification {
    pair: String,
    pairing: bool,
}
#[derive(Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
struct Identity {
    id: String,
    name: String,
    port: u16,
}
#[derive(Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
struct Offer {
    identity: Identity,
    pair: String,
    key: String,
}
#[derive(Default)]
struct ExchangeStats {
    sent_bytes: usize,
    received_bytes: usize,
    sent_events: usize,
    received_events: usize,
}
impl Service {
    fn identity(&self) -> Result<Identity, String> {
        Ok(Identity {
            id: self.id.clone(),
            name: lock(&self.runtime)?.config.name.clone(),
            port: self.port,
        })
    }
    fn validate_identity(&self, identity: &Identity, expected: Option<&str>) -> Result<(), String> {
        if identity.id == self.id
            || identity.id.is_empty()
            || identity.id.len() > 128
            || identity.name.is_empty()
            || identity.name.len() > 100
            || !valid_port(identity.port)
            || expected.is_some_and(|id| id != identity.id)
        {
            return Err("Wrong device identity. Create a fresh invitation for each device.".into());
        }
        Ok(())
    }
    #[cfg(test)]
    fn pair_at(&self, invitation: Peer, target: SocketAddr) -> Result<(), String> {
        let epoch = lock(&self.runtime)?.pairing_epoch;
        self.pair_at_epoch(invitation, target, epoch)
    }
    fn pair_at_epoch(
        &self,
        invitation: Peer,
        target: SocketAddr,
        epoch: u64,
    ) -> Result<(), String> {
        if lock(&self.runtime)?.pairing_epoch != epoch {
            return Err("Pairing revoked. Create a new invitation.".into());
        }
        let socket = TcpStream::connect_timeout(&target, Duration::from_secs(3))
            .map_err(|e| connect_error(target, &e))?;
        let mut socket = Incoming::new(socket, &self.stopped, Instant::now() + AUTH_TIMEOUT)?;
        negotiate(&mut socket, true)?;
        write_frame(
            &mut socket,
            &serde_json::to_vec(&Identification {
                pair: invitation.pair.clone(),
                pairing: true,
            })
            .map_err(err)?,
        )?;
        let mut noise = handshake(&mut socket, &key(&invitation.key)?, true).map_err(|_| {
            "Pairing could not finish. Create a new invitation and try again.".to_string()
        })?;
        send(&mut socket, &mut noise, &self.identity()?)?;
        let offer: Offer = recv_small(&mut socket, &mut noise)?;
        self.validate_identity(&offer.identity, Some(&invitation.id))?;
        if offer.pair.is_empty()
            || offer.pair.len() > 128
            || offer.pair == invitation.pair
            || offer.key == invitation.key
        {
            return Err("Invalid pairing credential".into());
        }
        let permanent = key(&offer.key)?;
        let peer = Peer {
            id: offer.identity.id,
            name: offer.identity.name,
            address: target.to_string(),
            pair: offer.pair,
            key: offer.key,
            last_sync: None,
            acknowledged: None,
        };
        // Durable preparation contains only the new credential. It is not trust
        // for recipes until fresh-key authentication. Preserve it across lost final
        // replies/restarts; a fresh invitation replaces the matching attempt.
        self.stage_peer(peer.clone(), epoch)?;
        send(&mut socket, &mut noise, &Receipt { version: VERSION })?;
        check_receipt(recv_small(&mut socket, &mut noise)?)?;
        drop(noise);
        drop(invitation);
        // Standard fresh Noise session proves both sides retained the new key.
        let mut noise = handshake(&mut socket, &permanent, true)?;
        send(&mut socket, &mut noise, &self.identity()?)?;
        let identity: Identity = recv_small(&mut socket, &mut noise)?;
        self.validate_identity(&identity, Some(&peer.id))?;
        self.confirm_peer(&peer, Some(epoch))?;
        Ok(())
    }
    fn receive_pairing(
        &self,
        socket: &mut Incoming<'_>,
        pair: &str,
        addr: SocketAddr,
    ) -> Result<(), String> {
        let (invitation, epoch) = {
            let mut rt = lock(&self.runtime)?;
            self.expire_invitation(&mut rt)?;
            if !rt.pending.as_ref().is_some_and(|p| p.invite.pair == pair) {
                return Err("Invitation expired or used. Create a new invitation.".into());
            }
            // Claim under the lock before any network I/O: one attempt, one device.
            (rt.pending.take().unwrap().invite, rt.pairing_epoch)
        };
        let mut noise = handshake(socket, &key(&invitation.key)?, false)?;
        drop(invitation);
        let identity: Identity = recv_small(socket, &mut noise)?;
        self.validate_identity(&identity, None)?;
        let permanent = snow::Builder::new(PATTERN.parse().map_err(err)?)
            .generate_keypair()
            .map_err(err)?
            .private;
        let permanent_pair = Uuid::new_v4().to_string();
        let peer = Peer {
            id: identity.id,
            name: identity.name,
            address: format!("{}:{}", addr.ip(), identity.port),
            pair: permanent_pair.clone(),
            key: B64.encode(&permanent),
            last_sync: None,
            acknowledged: None,
        };
        send(
            socket,
            &mut noise,
            &Offer {
                identity: self.identity()?,
                pair: permanent_pair,
                key: peer.key.clone(),
            },
        )?;
        check_receipt(recv_small(socket, &mut noise)?)?;
        self.stage_peer(peer.clone(), epoch)?;
        send(socket, &mut noise, &Receipt { version: VERSION })?;
        drop(noise);
        let mut noise = handshake(socket, &key(&peer.key)?, false)?;
        let identity: Identity = recv_small(socket, &mut noise)?;
        self.validate_identity(&identity, Some(&peer.id))?;
        self.confirm_peer(&peer, Some(epoch))?;
        send(socket, &mut noise, &self.identity()?)?;
        Ok(())
    }
    pub fn new(db: Arc<Mutex<Connection>>) -> Result<Self, String> {
        Self::with_port(db, PORT)
    }
    pub fn with_port(db: Arc<Mutex<Connection>>, port: u16) -> Result<Self, String> {
        if !valid_port(port) {
            return Err("Invalid cookdex sync port".into());
        }
        let (id, config) = {
            let conn = lock(&db)?;
            let id = conn
                .query_row("SELECT device_id FROM state WHERE id=1", [], |r| r.get(0))
                .map_err(err)?;
            let mut config: Config = storage::local(&conn, "syncConfig")?
                .map(serde_json::from_value)
                .transpose()
                .map_err(err)?
                .unwrap_or_default();
            if config.protocol > VERSION {
                return Err(NEWER_VERSION_ERROR.into());
            }
            if config.protocol != VERSION {
                config.re_pair_required |= !config.peers.is_empty();
                config.peers.clear();
                config.staged.clear();
                config.protocol = VERSION;
                // One atomic local-row replacement. No recipe/history/schema writes.
                storage::put_local(
                    &conn,
                    "syncConfig",
                    &serde_json::to_value(&config).map_err(err)?,
                )?;
            }
            (id, config)
        };
        Ok(Self {
            db,
            runtime: Arc::new(Mutex::new(Runtime {
                config,
                pending: None,
                pairing_epoch: 0,
                started: false,
                error: None,
                retries: BTreeMap::new(),
                reports: BTreeMap::new(),
                inbound_interruptions: 0,
            })),
            active: Arc::new(AtomicBool::new(false)),
            inbound: Arc::new(AtomicUsize::new(0)),
            admission: Arc::new(Mutex::new(Admission::default())),
            stopped: Arc::new(AtomicBool::new(false)),
            listener_port: Arc::new(AtomicU16::new(0)),
            workers: Arc::new(Mutex::new(Vec::new())),
            receivers: Arc::new(Mutex::new(Vec::new())),
            id,
            port,
            host_active: Arc::new(AtomicBool::new(false)),
            outgoing: Arc::new(Mutex::new(())),
            on_change: Arc::new(Mutex::new(None)),
        })
    }
    pub fn on_change(&self, callback: Arc<dyn Fn(i64, Vec<String>) + Send + Sync>) {
        *self.on_change.lock().unwrap() = Some(callback);
    }
    fn snapshot_before_sync(&self, peer: &Peer) {
        if let Ok(mut db) = self.db.lock() {
            if peer.last_sync.is_none() {
                crate::rolling_snapshots::before_sync(&mut db, &peer.pair);
            } else {
                crate::rolling_snapshots::attempt(&mut db, "automatic");
            }
        }
    }
    fn merge_remote(&self, packet: sync_store::Packet) -> Result<(), String> {
        let ids = packet
            .events
            .iter()
            .map(|e| e.recipe_id.clone())
            .collect::<BTreeSet<_>>()
            .into_iter()
            .collect();
        let mut db = lock(&self.db)?;
        let before: i64 = db
            .query_row("SELECT generation FROM state WHERE id=1", [], |r| r.get(0))
            .map_err(err)?;
        sync_store::merge(&mut db, packet, &chrono::Utc::now().to_rfc3339())?;
        crate::rolling_snapshots::attempt(&mut db, "automatic");
        let after: i64 = db
            .query_row("SELECT generation FROM state WHERE id=1", [], |r| r.get(0))
            .map_err(err)?;
        if before != after {
            if let Some(callback) = lock(&self.on_change)?.as_ref() {
                callback(after, ids);
            }
        }
        Ok(())
    }
    fn persist(&self, config: &Config) -> Result<(), String> {
        storage::put_local(
            &*lock(&self.db)?,
            "syncConfig",
            &serde_json::to_value(config).map_err(err)?,
        )
    }
    pub fn dismiss_pairing_notice(&self) -> Result<(), String> {
        let mut rt = lock(&self.runtime)?;
        let mut next = rt.config.clone();
        next.re_pair_required = false;
        self.persist(&next)?;
        rt.config = next;
        Ok(())
    }
    fn expire_invitation(&self, rt: &mut Runtime) -> Result<(), String> {
        if rt
            .pending
            .as_ref()
            .is_some_and(|p| p.expires <= Instant::now())
        {
            rt.pending = None;
        }
        Ok(())
    }
    fn stage_peer(&self, peer: Peer, epoch: u64) -> Result<(), String> {
        let mut rt = lock(&self.runtime)?;
        self.expire_invitation(&mut rt)?;
        if rt.pairing_epoch != epoch {
            return Err("Invitation revoked. Create a new invitation.".into());
        }
        self.check_outgoing(&rt, &peer, false)?;
        let mut next = rt.config.clone();
        next.staged.retain(|p| p.peer.id != peer.id);
        next.staged.push(StagedPeer { peer });
        self.persist(&next)?;
        rt.config = next;
        Ok(())
    }
    fn confirm_peer(&self, peer: &Peer, epoch: Option<u64>) -> Result<(), String> {
        let mut rt = lock(&self.runtime)?;
        if epoch.is_some_and(|epoch| epoch != rt.pairing_epoch) {
            return Err("Pairing revoked. Create a new invitation.".into());
        }
        self.check_outgoing(&rt, peer, true)?;
        let mut next = rt.config.clone();
        next.staged.retain(|p| p.peer.pair != peer.pair);
        next.peers.retain(|p| p.id != peer.id);
        next.peers.push(peer.clone());
        self.persist(&next)?;
        rt.config = next;
        Ok(())
    }
    pub fn report_engine_error(&self, error: String) {
        if !error.starts_with("Sync is paused") && !error.starts_with("Sync paused") {
            if let Ok(mut rt) = self.runtime.lock() {
                rt.error = Some(error);
            }
        }
    }
    pub fn status(&self) -> Result<Value, String> {
        let mut rt = lock(&self.runtime)?;
        self.expire_invitation(&mut rt)?;
        let conn = lock(&self.db)?;
        let generation: i64 = conn
            .query_row("SELECT generation FROM state WHERE id=1", [], |r| r.get(0))
            .map_err(err)?;
        let current = history_identity(&conn)?;
        let error = if storage::set_aside_ids(&conn)?.is_empty() {
            rt.error.clone()
        } else {
            Some(sync_store::SET_ASIDE_ERROR.to_string())
        };
        let public_peer = |p: &Peer, pending: bool| json!({"id":p.id,"name":p.name,"address":p.address,"lastSync":p.last_sync,"caughtUp":!pending && p.acknowledged.as_ref()==Some(&current),"pairingPending":pending});
        let peers: Vec<_> = rt
            .config
            .peers
            .iter()
            .filter(|p| !rt.config.staged.iter().any(|s| s.peer.id == p.id))
            .map(|p| public_peer(p, false))
            .chain(rt.config.staged.iter().map(|p| public_peer(&p.peer, true)))
            .collect();
        Ok(
            json!({"rePairRequired":rt.config.re_pair_required,"enabled":rt.config.enabled,"active":self.active.load(Ordering::SeqCst),"name":rt.config.name,"deviceId":self.id,"addresses":addresses(),"port":self.port,"error":error,"invitationId":rt.pending.as_ref().filter(|p|p.expires>Instant::now()).map(|p|&p.invite.pair),"generation":generation,"reports":rt.reports.iter().filter(|(id,_)|rt.config.peers.iter().any(|p|p.id==**id)).map(|(id,r)|{let mut r=r.clone();if r["status"]=="waiting" {r["retryAfterSeconds"]=json!(rt.retry_after(id,false,Instant::now()).unwrap_or(0));}r}).collect::<Vec<_>>(),"conflicts":sync_store::conflicts(&conn)?,"peers":peers}),
        )
    }
    pub fn next_retry(&self) -> Option<Instant> {
        self.runtime
            .lock()
            .ok()?
            .retries
            .values()
            .map(|r| r.next)
            .min()
    }
    pub fn configure(&self, enabled: bool, name: String) -> Result<(), String> {
        if name.trim().is_empty() || name.len() > 100 {
            return Err("Choose a device name of 1–100 characters".into());
        }
        {
            let mut rt = lock(&self.runtime)?;
            let mut next = rt.config.clone();
            next.enabled = enabled;
            next.name = name.trim().into();
            self.persist(&next)?;
            rt.config = next;
            if !enabled {
                rt.pending = None;
                rt.pairing_epoch = rt.pairing_epoch.wrapping_add(1);
            }
        }
        self.foreground(self.host_active.load(Ordering::SeqCst))
    }
    pub fn foreground(&self, visible: bool) -> Result<(), String> {
        self.host_active.store(visible, Ordering::SeqCst);
        let mut rt = lock(&self.runtime)?;
        if self.stopped.load(Ordering::SeqCst) {
            return Err("Session closed".into());
        }
        let active = visible && rt.config.enabled;
        if active && !rt.started {
            let (listener, udp) = bind_listeners(self.port)?;
            self.listener_port
                .store(listener.local_addr().map_err(err)?.port(), Ordering::SeqCst);
            let server = self.clone();
            lock(&self.workers)?.push(std::thread::spawn(move || server.listen(listener)));
            let server = self.clone();
            lock(&self.workers)?.push(std::thread::spawn(move || server.discover_listener(udp)));
            rt.started = true;
        }
        if active && !self.active.load(Ordering::SeqCst) {
            rt.retries.clear();
        }
        self.active.store(active, Ordering::SeqCst);

        Ok(())
    }
    /// Session owner calls once before dropping the database. No polling wakeups.
    pub fn shutdown(&self) {
        self.active.store(false, Ordering::SeqCst);
        self.stopped.store(true, Ordering::SeqCst);
        let Ok(mut workers) = self.workers.lock() else {
            return;
        };
        if workers.is_empty() {
            return;
        }
        let port = self.listener_port.load(Ordering::SeqCst);
        let _ = TcpStream::connect_timeout(
            &SocketAddr::from((Ipv4Addr::LOCALHOST, port)),
            Duration::from_secs(1),
        );
        if let Ok(socket) = UdpSocket::bind((Ipv4Addr::LOCALHOST, 0)) {
            let _ = socket.send_to(b"shutdown", (Ipv4Addr::LOCALHOST, port));
        }
        for worker in workers.drain(..) {
            let _ = worker.join();
        }
        // Listeners have exited: no further receiver can be spawned. Shut down
        // accepted sockets to interrupt their blocking reads before joining.
        let receivers = self
            .receivers
            .lock()
            .map(|mut r| std::mem::take(&mut *r))
            .unwrap_or_default();
        for (socket, _) in &receivers {
            let _ = socket.shutdown(Shutdown::Both);
        }
        for (_, worker) in receivers {
            let _ = worker.join();
        }
    }
    fn listen(&self, listener: TcpListener) {
        // Blocking accept sleeps in the OS until a connection arrives, including
        // while hidden. The bound port is reused on the next foreground transition.
        loop {
            match listener.accept() {
                Ok((stream, addr)) => {
                    if self.stopped.load(Ordering::SeqCst) {
                        return;
                    }
                    if !self.active.load(Ordering::SeqCst) || !private(addr.ip()) {
                        drop(stream);
                        continue;
                    }
                    let accepted = Instant::now();
                    if !self
                        .admission
                        .lock()
                        .is_ok_and(|mut a| a.acquire(addr.ip(), accepted))
                    {
                        continue;
                    }
                    let permit = AdmissionGuard {
                        admission: self.admission.clone(),
                        ip: addr.ip(),
                        authenticated: false,
                    };
                    if self.inbound.fetch_add(1, Ordering::SeqCst) >= 4 {
                        self.inbound.fetch_sub(1, Ordering::SeqCst);
                        drop(stream);
                        continue;
                    }
                    let Ok(socket) = stream.try_clone() else {
                        self.inbound.fetch_sub(1, Ordering::SeqCst);
                        continue;
                    };
                    let Ok(mut receivers) = self.receivers.lock() else {
                        self.inbound.fetch_sub(1, Ordering::SeqCst);
                        continue;
                    };
                    // Reap completed receivers instead of accumulating handles.
                    let mut remaining = Vec::new();
                    for (socket, worker) in receivers.drain(..) {
                        if worker.is_finished() {
                            let _ = worker.join();
                        } else {
                            remaining.push((socket, worker));
                        }
                    }
                    *receivers = remaining;
                    let server = self.clone();
                    let worker = std::thread::spawn(move || {
                        if let Err(error) = server.receive_admitted(
                            stream,
                            addr,
                            accepted + AUTH_TIMEOUT,
                            Some(permit),
                        ) {
                            if let Ok(mut rt) = server.runtime.lock() {
                                if transient_transfer(&error) {
                                    rt.inbound_interruptions =
                                        rt.inbound_interruptions.saturating_add(1);
                                    if rt.inbound_interruptions >= 3 {
                                        rt.error = Some(format!(
                                            "Incoming transfers keep stopping: {error}. Keep both devices open on the same Wi-Fi, then tap Sync now."
                                        ));
                                    }
                                } else {
                                    rt.error = Some(format!("Incoming connection: {error}"));
                                }
                            }
                        }
                        server.inbound.fetch_sub(1, Ordering::SeqCst);
                    });
                    receivers.push((socket, worker));
                }
                Err(e)
                    if matches!(
                        e.kind(),
                        std::io::ErrorKind::Interrupted | std::io::ErrorKind::ConnectionAborted
                    ) =>
                {
                    continue;
                }
                Err(e) => {
                    if let Ok(mut rt) = self.runtime.lock() {
                        rt.error = Some(format!("LAN listener stopped: {e}"));
                    }
                    return;
                }
            }
        }
    }
    fn discover_listener(&self, socket: UdpSocket) {
        // No receive timeout: discovery has no periodic idle wakeups.
        let mut bytes = [0u8; 128];
        loop {
            match socket.recv_from(&mut bytes) {
                Ok((n, addr)) => {
                    if self.stopped.load(Ordering::SeqCst) {
                        return;
                    }
                    if self.active.load(Ordering::SeqCst)
                        && private(addr.ip())
                        && bytes[..n] == *format!("{DOMAIN} {}", self.id).as_bytes()
                    {
                        let _ = socket.send_to(&bytes[..n], addr);
                    }
                }
                // A UDP reply to a client that has just closed can surface an
                // ICMP error on the next receive, especially on Windows.
                Err(e)
                    if matches!(
                        e.kind(),
                        std::io::ErrorKind::Interrupted
                            | std::io::ErrorKind::ConnectionReset
                            | std::io::ErrorKind::ConnectionRefused
                    ) =>
                {
                    continue;
                }
                Err(e) => {
                    if let Ok(mut rt) = self.runtime.lock() {
                        rt.error = Some(format!("LAN discovery stopped: {e}"));
                    }
                    return;
                }
            }
        }
    }
    pub fn invitation(&self, address: String) -> Result<String, String> {
        if !self.active.load(Ordering::SeqCst) {
            return Err("Enable sync first".into());
        }
        let ip: Ipv4Addr = address
            .parse()
            .map_err(|_| "Choose this device’s local network address")?;
        if !addresses().contains(&ip.to_string())
            && !(ip.is_loopback() && !cfg!(feature = "production-sync"))
        {
            return Err("Address is not on this device".into());
        }
        let secret = snow::Builder::new(PATTERN.parse().map_err(err)?)
            .generate_keypair()
            .map_err(err)?
            .private;
        let mut rt = lock(&self.runtime)?;
        let invite = Invitation {
            domain: DOMAIN.into(),
            version: VERSION,
            id: self.id.clone(),
            name: rt.config.name.clone(),
            address: format!("{ip}:{}", self.port),
            // A desktop can expose virtual/VPN adapters before its LAN adapter.
            // The selected address stays first; bounded alternatives avoid
            // making successful pairing depend on adapter enumeration order.
            alternatives: addresses()
                .into_iter()
                .filter(|a| a != &ip.to_string())
                .take(7)
                .map(|a| format!("{a}:{}", self.port))
                .collect(),
            pair: Uuid::new_v4().to_string(),
            key: B64.encode(secret),
        };
        let code = format!(
            "recipe-pair:{}",
            B64.encode(serde_json::to_vec(&invite).map_err(err)?)
        );
        rt.error = None;
        rt.pairing_epoch = rt.pairing_epoch.wrapping_add(1);
        rt.pending = Some(Pending {
            invite,
            expires: Instant::now() + Duration::from_secs(600),
        });
        Ok(code)
    }
    pub fn pair(&self, code: String) -> Result<(), String> {
        if !self.active.load(Ordering::SeqCst) {
            return Err("Enable sync first".into());
        }
        let epoch = lock(&self.runtime)?.pairing_epoch;
        if code.len() > 4096 {
            return Err("Invalid invitation".into());
        }
        let invite: Invitation = serde_json::from_slice(
            &B64.decode(
                code.trim()
                    .strip_prefix("recipe-pair:")
                    .ok_or("Paste a recipe pairing invitation")?,
            )
            .map_err(err)?,
        )
        .map_err(err)?;
        if invite.version != VERSION {
            return Err(version_message(invite.version).into());
        }
        if invite.domain != DOMAIN
            || invite.id == self.id
            || invite.name.len() > 100
            || invite.id.len() > 128
            || invite.pair.len() > 128
        {
            return Err("Invalid pairing invitation or same device".into());
        }
        let targets = invitation_targets(&invite)?;
        let peer = Peer {
            id: invite.id,
            name: invite.name,
            address: invite.address,
            pair: invite.pair,
            key: invite.key,
            last_sync: None,
            acknowledged: None,
        };
        let _outgoing = lock(&self.outgoing)?;
        let mut last_error = String::new();
        for target in targets {
            self.check_outgoing(&*lock(&self.runtime)?, &peer, false)?;
            match self.pair_at_epoch(peer.clone(), target, epoch) {
                Ok(()) => return Ok(()),
                // Retry another explicitly invited address only when the TCP
                // connection itself was unavailable, never an auth/merge error.
                Err(e) if e.starts_with("Device unavailable") => last_error = e,
                Err(e) if version_error(&e) => return Err(e),
                Err(_) => {
                    return Err(
                        "Pairing could not finish. Create a new invitation and try again.".into(),
                    );
                }
            }
        }
        Err(last_error)
    }
    pub fn forget(&self, id: &str) -> Result<(), String> {
        let mut rt = lock(&self.runtime)?;
        let mut next = rt.config.clone();
        next.peers.retain(|p| p.id != id);
        next.staged.retain(|p| p.peer.id != id);
        rt.pairing_epoch = rt.pairing_epoch.wrapping_add(1);
        rt.pending = None;
        self.persist(&next)?;
        rt.config = next;
        rt.retries.remove(id);
        rt.reports.remove(id);
        Ok(())
    }
    pub fn sync(&self) -> Result<Value, String> {
        self.sync_with_mode(true)
    }
    pub fn sync_with_mode(&self, force: bool) -> Result<Value, String> {
        self.sync_prepared(force, || {})
    }
    pub fn sync_prepared(&self, force: bool, begin: impl FnOnce()) -> Result<Value, String> {
        let _outgoing = lock(&self.outgoing)?;
        begin();
        self.sync_with_exchange(force, |peer| self.exchange(peer, true))
    }
    fn sync_with_exchange(
        &self,
        force: bool,
        mut exchange: impl FnMut(Peer) -> Result<(), String>,
    ) -> Result<Value, String> {
        if !self.active.load(Ordering::SeqCst) {
            return Err("Sync is paused while the app is closed or hidden".into());
        }
        let peers = {
            let mut rt = lock(&self.runtime)?;
            self.expire_invitation(&mut rt)?;
            let mut peers = rt.config.peers.clone();
            for staged in &rt.config.staged {
                peers.retain(|p| p.id != staged.peer.id);
                peers.push(staged.peer.clone());
            }
            peers
        };
        let mut reports = vec![];
        for peer in peers {
            if !self.active.load(Ordering::SeqCst) {
                return Err("Sync paused; retry when foregrounded".into());
            }
            let id = peer.id.clone();
            let name = peer.name.clone();
            {
                let rt = lock(&self.runtime)?;
                if let Some(seconds) = rt.retry_after(&id, force, Instant::now()) {
                    let mut report = rt.reports.get(&id).cloned().unwrap_or_else(
                        || json!({"id":id,"name":name,"ok":false,"status":"waiting","error":null}),
                    );
                    report["retryAfterSeconds"] = json!(seconds);
                    reports.push(report);
                    continue;
                }
            }
            let result = exchange(peer);
            let retry_after = {
                let mut rt = lock(&self.runtime)?;
                let at = Instant::now();
                // A device forgotten during the exchange must not retain retry state.
                if rt.config.peers.iter().any(|p| p.id == id)
                    || rt.config.staged.iter().any(|p| p.peer.id == id)
                {
                    rt.record_result(&id, &result, at);
                }
                rt.retry_after(&id, false, at)
            };
            let status = match &result {
                Ok(_) => "synced",
                Err(e) if e.starts_with("Device unavailable.") => "waiting",
                Err(e)
                    if transient_transfer(e)
                        && lock(&self.runtime)?
                            .retries
                            .get(&id)
                            .is_some_and(|r| r.failures < 3) =>
                {
                    "waiting"
                }
                Err(_) => "error",
            };
            let error = if status == "waiting" {
                None
            } else {
                result.as_ref().err()
            };
            let report = json!({"id":id,"name":name,"ok":result.is_ok(),"status":status,"error":error,"retryAfterSeconds":retry_after});
            lock(&self.runtime)?.reports.insert(id, report.clone());
            reports.push(report);
        }
        Ok(json!(reports))
    }
    fn exchange(&self, peer: Peer, discover: bool) -> Result<(), String> {
        {
            let rt = lock(&self.runtime)?;
            self.check_outgoing(&rt, &peer, discover)?;
        }
        let original = endpoint(&peer.address)?;
        let target = if discover {
            discover_peer(&peer.id, original.port()).unwrap_or(original)
        } else {
            original
        };
        self.exchange_at(peer, target, discover)
    }
    fn exchange_at(&self, peer: Peer, target: SocketAddr, discover: bool) -> Result<(), String> {
        self.exchange_at_counted(peer, target, discover).map(|_| ())
    }
    fn exchange_at_counted(
        &self,
        mut peer: Peer,
        target: SocketAddr,
        discover: bool,
    ) -> Result<ExchangeStats, String> {
        let socket = TcpStream::connect_timeout(&target, Duration::from_secs(3))
            .map_err(|e| connect_error(target, &e))?;
        let mut socket = Incoming::new(socket, &self.stopped, Instant::now() + AUTH_TIMEOUT)?;
        negotiate(&mut socket, true)?;
        write_frame(
            &mut socket,
            &serde_json::to_vec(&Identification {
                pair: peer.pair.clone(),
                pairing: false,
            })
            .map_err(err)?,
        )?;
        // The authenticated build-domain prologue prevents cross-channel trust,
        // even if somebody manually edits a development invitation's text.
        let mut noise = handshake(&mut socket, &key(&peer.key)?, true)
            .map_err(|e| connection_error("authenticating", e, !discover))?;
        send(&mut socket, &mut noise, &self.identity()?)?;
        let identity: Identity = recv_small(&mut socket, &mut noise)?;
        self.validate_identity(&identity, Some(&peer.id))?;
        self.confirm_peer(&peer, None)?;
        socket.deadline = None;
        let name = lock(&self.runtime)?.config.name.clone();
        let snapshot = sync_store::export(&*lock(&self.db)?)?;
        let manifest = sync_store::manifest(&snapshot)?;
        let inventory = Inventory {
            port: self.port,
            version: VERSION,
            id: self.id.clone(),
            name,
            summary: summary(&manifest)?,
        };
        let mut stats = ExchangeStats::default();
        stats.sent_bytes += send_counted(&mut socket, &mut noise, &inventory)?;
        let (reply, bytes) = recv_inventory(&mut socket, &mut noise)
            .map_err(|e| connection_error("negotiating sync version", e, !discover))?;
        stats.received_bytes += bytes;
        if reply.id != peer.id
            || reply.name.is_empty()
            || reply.name.len() > 100
            || !valid_port(reply.port)
        {
            return Err("Wrong device identity".into());
        }
        let remote_manifest = if inventory.summary == reply.summary {
            manifest.clone()
        } else {
            stats.sent_bytes += send_counted(&mut socket, &mut noise, &manifest)?;
            let (remote, bytes): (sync_store::Manifest, usize) =
                recv_counted(&mut socket, &mut noise)?;
            stats.received_bytes += bytes;
            check_summary(&remote, &reply.summary)?;
            remote
        };
        let delta = sync_store::delta(&snapshot, &remote_manifest)?;
        {
            let rt = lock(&self.runtime)?;
            self.check_outgoing(&rt, &peer, discover)?;
        }
        stats.sent_events = delta.events.len();
        stats.sent_bytes += send_counted(&mut socket, &mut noise, &delta)?;
        let (delta, bytes): (sync_store::Packet, usize) = recv_counted(&mut socket, &mut noise)
            .map_err(|e| connection_error("receiving recipe changes", e, !discover))?;
        stats.received_bytes += bytes;
        stats.received_events = delta.events.len();
        sync_store::validate_packet(&delta)?;
        {
            // Hold trust through the local commit, never across network I/O.
            let rt = lock(&self.runtime)?;
            self.check_outgoing(&rt, &peer, discover)?;
            self.snapshot_before_sync(&peer);
            self.merge_remote(delta)?;
        }
        stats.sent_bytes += send_counted(&mut socket, &mut noise, &Receipt { version: VERSION })?;
        let (receipt, bytes): (Receipt, usize) = recv_counted(&mut socket, &mut noise)
            .map_err(|e| connection_error("confirming sync", e, !discover))?;
        stats.received_bytes += bytes;
        if receipt.version != VERSION {
            return Err(VERSION_ERROR.into());
        }
        let mut rt = lock(&self.runtime)?;
        self.check_outgoing(&rt, &peer, discover)?;
        peer.address = target.to_string();
        peer.name = reply.name;
        peer.last_sync = Some(now());
        peer.acknowledged = Some(acknowledged_union(&manifest, &remote_manifest));
        let mut next = rt.config.clone();
        next.peers.retain(|p| p.id != peer.id);
        next.staged.retain(|p| p.peer.pair != peer.pair);
        rt.retries.remove(&peer.id);
        rt.reports.remove(&peer.id);
        next.peers.push(peer);
        self.persist(&next)?;
        rt.config = next;
        rt.error = None;
        Ok(stats)
    }
    fn check_outgoing(&self, rt: &Runtime, peer: &Peer, discover: bool) -> Result<(), String> {
        if !self.active.load(Ordering::SeqCst) {
            return Err("Sync paused; retry when foregrounded".into());
        }
        if discover
            && !rt
                .config
                .peers
                .iter()
                .any(|p| p.id == peer.id && p.pair == peer.pair && p.key == peer.key)
            && !rt
                .config
                .staged
                .iter()
                .any(|p| p.peer.id == peer.id && p.peer.pair == peer.pair && p.peer.key == peer.key)
        {
            return Err("Device was forgotten during sync".into());
        }
        if !rt.config.peers.iter().any(|p| p.id == peer.id)
            && !rt.config.staged.iter().any(|p| p.peer.id == peer.id)
            && rt.config.peers.len()
                + rt.config
                    .staged
                    .iter()
                    .filter(|p| !rt.config.peers.iter().any(|q| q.id == p.peer.id))
                    .count()
                >= 16
        {
            return Err("At most 16 paired devices are supported".into());
        }
        Ok(())
    }
    fn check_incoming(
        &self,
        rt: &Runtime,
        pair: &str,
        id: &str,
        secret: &[u8; 32],
        _is_new: bool,
    ) -> Result<(), String> {
        if !self.active.load(Ordering::SeqCst) {
            return Err("Sync paused".into());
        }
        let known = rt
            .config
            .peers
            .iter()
            .any(|p| p.pair == pair && p.id == id && p.key == B64.encode(secret));
        if !known {
            return Err("Pairing expired or revoked".into());
        }
        if !known && rt.config.peers.len() >= 16 {
            return Err("Too many paired devices".into());
        }
        Ok(())
    }
    #[cfg(test)]
    fn receive(&self, socket: TcpStream, addr: SocketAddr) -> Result<(), String> {
        self.receive_admitted(socket, addr, Instant::now() + AUTH_TIMEOUT, None)
    }
    fn receive_admitted(
        &self,
        socket: TcpStream,
        addr: SocketAddr,
        deadline: Instant,
        mut permit: Option<AdmissionGuard>,
    ) -> Result<(), String> {
        let mut socket = Incoming::new(socket, &self.stopped, deadline)?;
        negotiate(&mut socket, false)?;
        let identification: Identification = serde_json::from_slice(&read_frame(&mut socket, 512)?)
            .map_err(|_| "Invalid connection identification".to_string())?;
        let pair = identification.pair;
        if pair.is_empty() || pair.len() > 128 {
            return Err("Invalid pairing identifier".into());
        }
        if identification.pairing {
            let result = self.receive_pairing(&mut socket, &pair, addr);
            if result.is_ok() {
                if let Some(permit) = &mut permit {
                    permit.authenticated();
                }
            }
            return result;
        }
        let peer = {
            let mut rt = lock(&self.runtime)?;
            self.expire_invitation(&mut rt)?;
            rt.config
                .peers
                .iter()
                .find(|p| p.pair == pair)
                .cloned()
                .or_else(|| {
                    rt.config
                        .staged
                        .iter()
                        .find(|p| p.peer.pair == pair)
                        .map(|p| p.peer.clone())
                })
                .ok_or("Device not paired. Create a new invitation.")?
        };
        let secret = key(&peer.key)?;
        let expected = Some(peer.id.clone());
        let is_new = false;
        let mut noise = handshake(&mut socket, &secret, false)?;
        let identity: Identity = recv_small(&mut socket, &mut noise)?;
        self.validate_identity(&identity, Some(&peer.id))?;
        self.confirm_peer(&peer, None)?;
        send(&mut socket, &mut noise, &self.identity()?)?;
        if let Some(permit) = &mut permit {
            permit.authenticated();
        }
        socket.deadline = None;
        let (request, _) = match recv_inventory(&mut socket, &mut noise) {
            Ok(request) => request,
            Err(error) => {
                let _ = send(
                    &mut socket,
                    &mut noise,
                    &json!({"version":VERSION,"error":error}),
                );
                return Err(error);
            }
        };
        if request.id == self.id
            || !valid_port(request.port)
            || request.id.is_empty()
            || request.id.len() > 128
            || request.name.is_empty()
            || request.name.len() > 100
            || expected.as_ref().is_some_and(|id| *id != request.id)
        {
            return Err("This invitation belongs to another device, or the device identity was invalid. Create a fresh invitation for each new device.".into());
        }
        {
            let rt = lock(&self.runtime)?;
            self.check_incoming(&rt, &pair, &request.id, &secret, is_new)?;
        }
        // Manifest and delta both use this immutable snapshot. Edits made while
        // networking is in progress are safely picked up on the next exchange.
        let snapshot = sync_store::export(&*lock(&self.db)?)?;
        let manifest = sync_store::manifest(&snapshot)?;
        let local_summary = summary(&manifest)?;
        let name = lock(&self.runtime)?.config.name.clone();
        send(
            &mut socket,
            &mut noise,
            &Inventory {
                port: self.port,
                version: VERSION,
                id: self.id.clone(),
                name,
                summary: summary(&manifest)?,
            },
        )?;
        let remote_manifest = if local_summary == request.summary {
            manifest.clone()
        } else {
            let remote: sync_store::Manifest = recv(&mut socket, &mut noise)?;
            check_summary(&remote, &request.summary)?;
            // Validate identities before advertising any recipe changes.
            sync_store::delta(&snapshot, &remote)?;
            send(&mut socket, &mut noise, &manifest)?;
            remote
        };
        let delta = sync_store::delta(&snapshot, &remote_manifest)?;
        let incoming: sync_store::Packet = recv(&mut socket, &mut noise)?;
        sync_store::validate_packet(&incoming)?;
        {
            let rt = lock(&self.runtime)?;
            self.check_incoming(&rt, &pair, &request.id, &secret, is_new)?;
        }
        send(&mut socket, &mut noise, &delta)?;
        let receipt: Receipt = recv(&mut socket, &mut noise)?;
        if receipt.version != VERSION {
            return Err(VERSION_ERROR.into());
        }
        {
            let mut rt = lock(&self.runtime)?;
            self.check_incoming(&rt, &pair, &request.id, &secret, is_new)?;
            self.snapshot_before_sync(&peer);
            self.merge_remote(incoming)?;
            let mut next = rt.config.clone();
            next.peers.retain(|p| p.id != request.id);
            next.staged.retain(|p| p.peer.pair != pair);
            rt.retries.remove(&request.id);
            rt.reports.remove(&request.id);
            rt.inbound_interruptions = 0;
            next.peers.push(Peer {
                id: request.id,
                name: request.name,
                address: format!("{}:{}", addr.ip(), request.port),
                pair,
                key: B64.encode(secret),
                last_sync: Some(now()),
                acknowledged: Some(acknowledged_union(&manifest, &remote_manifest)),
            });
            self.persist(&next)?;
            rt.config = next;
            if is_new {
                rt.pending = None;
            }
            rt.error = None;
        }
        // If either final acknowledgement is lost, retained revisions and
        // idempotent merging make a fresh inventory exchange safe to retry.
        send(&mut socket, &mut noise, &Receipt { version: VERSION })?;
        Ok(())
    }
    pub fn resolve(
        &self,
        recipe_id: String,
        heads: Vec<String>,
        choice: String,
    ) -> Result<(), String> {
        sync_store::resolve(
            &mut *lock(&self.db)?,
            &recipe_id,
            &heads,
            &choice,
            &chrono::Utc::now().to_rfc3339(),
        )
    }
}
fn bind_listeners(port: u16) -> Result<(TcpListener, UdpSocket), String> {
    let listener = TcpListener::bind((Ipv4Addr::UNSPECIFIED, port)).map_err(|e| {
        format!("Cannot listen on port {port}: {e}. Close other copies of this app.")
    })?;
    let bound_port = listener.local_addr().map_err(err)?.port();
    let udp = UdpSocket::bind((Ipv4Addr::UNSPECIFIED, bound_port)).map_err(err)?;
    Ok((listener, udp))
}
fn private(ip: IpAddr) -> bool {
    matches!(ip,IpAddr::V4(v) if v.is_private()||v.is_loopback()||v.is_link_local())
}
fn default_port() -> u16 {
    PORT
}
fn valid_port(port: u16) -> bool {
    if cfg!(feature = "production-sync") {
        port == 47831
    } else {
        port >= 1024 && port != 47831
    }
}
fn endpoint(text: &str) -> Result<SocketAddr, String> {
    let addr: SocketAddr = text.parse().map_err(|_| "Invalid local address")?;
    if !private(addr.ip()) || !valid_port(addr.port()) {
        return Err("Sync only accepts local IPv4 addresses on the recipe sync port".into());
    }
    Ok(addr)
}
fn invitation_targets(invite: &Invitation) -> Result<Vec<SocketAddr>, String> {
    if invite.alternatives.len() > 7 {
        return Err("Too many invitation addresses".into());
    }
    let primary = endpoint(&invite.address)?;
    let mut result = vec![primary];
    for candidate in &invite.alternatives {
        let addr = endpoint(candidate)?;
        if addr.port() != primary.port() {
            return Err("Invalid invitation port".into());
        }
        if !result.contains(&addr) {
            result.push(addr);
        }
    }
    Ok(result)
}
fn addresses() -> Vec<String> {
    if_addrs::get_if_addrs()
        .unwrap_or_default()
        .into_iter()
        .filter_map(|i| match i.addr {
            if_addrs::IfAddr::V4(v) if !v.ip.is_loopback() && private(IpAddr::V4(v.ip)) => {
                Some(v.ip.to_string())
            }
            _ => None,
        })
        .collect::<BTreeSet<_>>()
        .into_iter()
        .collect()
}
fn discover_peer(id: &str, port: u16) -> Option<SocketAddr> {
    let socket = UdpSocket::bind((Ipv4Addr::UNSPECIFIED, 0)).ok()?;
    socket.set_broadcast(true).ok()?;
    socket
        .set_read_timeout(Some(Duration::from_millis(150)))
        .ok()?;
    let msg = format!("{DOMAIN} {id}");
    let _ = socket.send_to(msg.as_bytes(), (Ipv4Addr::BROADCAST, port));
    for i in if_addrs::get_if_addrs().ok()? {
        if let if_addrs::IfAddr::V4(v) = i.addr {
            if let Some(broadcast) = v.broadcast {
                let _ = socket.send_to(msg.as_bytes(), (broadcast, port));
            }
        }
    }
    let end = Instant::now() + Duration::from_millis(450);
    let mut bytes = [0u8; 128];
    while Instant::now() < end {
        if let Ok((n, addr)) = socket.recv_from(&mut bytes) {
            if private(addr.ip()) && bytes[..n] == *msg.as_bytes() {
                return Some(SocketAddr::new(addr.ip(), port));
            }
        }
    }
    None
}
fn key(text: &str) -> Result<[u8; 32], String> {
    B64.decode(text)
        .map_err(err)?
        .try_into()
        .map_err(|_| "Invalid pairing secret".into())
}
trait Transport: Read + Write {}
impl<T: Read + Write> Transport for T {}

struct Incoming<'a> {
    socket: TcpStream,
    stopped: &'a AtomicBool,
    deadline: Option<Instant>,
}
impl Drop for Incoming<'_> {
    fn drop(&mut self) {
        let _ = self.socket.shutdown(Shutdown::Both);
    }
}
impl Incoming<'_> {
    fn new(
        socket: TcpStream,
        stopped: &AtomicBool,
        deadline: Instant,
    ) -> Result<Incoming<'_>, String> {
        socket.set_nonblocking(false).map_err(err)?;
        socket
            .set_read_timeout(Some(Duration::from_millis(100)))
            .map_err(err)?;
        socket
            .set_write_timeout(Some(Duration::from_millis(100)))
            .map_err(err)?;
        Ok(Incoming {
            socket,
            stopped,
            deadline: Some(deadline),
        })
    }
    fn io<T>(
        &self,
        mut operation: impl FnMut(&TcpStream) -> std::io::Result<T>,
    ) -> std::io::Result<T> {
        let deadline = self
            .deadline
            .unwrap_or_else(|| Instant::now() + Duration::from_secs(15));
        loop {
            if Instant::now() >= deadline {
                return Err(std::io::Error::new(
                    std::io::ErrorKind::TimedOut,
                    "Connection authentication timed out",
                ));
            }
            if self.stopped.load(Ordering::SeqCst) {
                return Err(std::io::Error::new(
                    std::io::ErrorKind::ConnectionAborted,
                    "Session closed",
                ));
            }
            let remaining = deadline
                .saturating_duration_since(Instant::now())
                .min(Duration::from_millis(100));
            if remaining.is_zero() {
                return Err(std::io::ErrorKind::TimedOut.into());
            }
            self.socket.set_read_timeout(Some(remaining))?;
            self.socket.set_write_timeout(Some(remaining))?;
            match operation(&self.socket) {
                Err(e)
                    if matches!(
                        e.kind(),
                        std::io::ErrorKind::TimedOut | std::io::ErrorKind::WouldBlock
                    ) && Instant::now() < deadline =>
                {
                    continue;
                }
                result => return result,
            }
        }
    }
}

fn version_message(version: u32) -> &'static str {
    if version > VERSION {
        NEWER_VERSION_ERROR
    } else {
        VERSION_ERROR
    }
}
fn version_error(error: &str) -> bool {
    error.contains(VERSION_ERROR) || error.contains(NEWER_VERSION_ERROR)
}
// Framed, public version gate is the first application data in each direction.
// A v3 listener treats this as an unknown pairing ID and closes without Noise.
fn negotiate(s: &mut impl Transport, initiator: bool) -> Result<(), String> {
    let hello = format!("cookdex-sync/{VERSION}");
    if initiator {
        write_frame(s, hello.as_bytes()).map_err(|_| VERSION_ERROR.to_string())?;
    }
    let remote = read_frame(s, 128).map_err(|_| VERSION_ERROR.to_string())?;
    if !initiator {
        write_frame(s, hello.as_bytes())?;
    }
    let version = std::str::from_utf8(&remote)
        .ok()
        .and_then(|s| s.strip_prefix("cookdex-sync/"))
        .and_then(|s| s.parse::<u32>().ok())
        .unwrap_or(3);
    if version != VERSION {
        return Err(version_message(version).into());
    }
    Ok(())
}
fn check_receipt(receipt: Receipt) -> Result<(), String> {
    if receipt.version == VERSION {
        Ok(())
    } else {
        Err(version_message(receipt.version).into())
    }
}
fn recv_small<T: for<'de> Deserialize<'de>>(
    s: &mut impl Transport,
    n: &mut snow::TransportState,
) -> Result<T, String> {
    let mut bytes = Vec::new();
    let mut out = [0u8; 4096];
    loop {
        let frame = read_frame(s, 4096)?;
        let len = n.read_message(&frame, &mut out).map_err(err)?;
        if len == 0 {
            break;
        }
        if bytes.len() + len > 4096 {
            return Err("Oversized authentication message".into());
        }
        bytes.extend_from_slice(&out[..len]);
    }
    serde_json::from_slice(&bytes).map_err(|_| "Invalid authentication message".into())
}
impl Read for Incoming<'_> {
    fn read(&mut self, bytes: &mut [u8]) -> std::io::Result<usize> {
        self.io(|mut socket| socket.read(bytes))
    }
}
impl Write for Incoming<'_> {
    fn write(&mut self, bytes: &[u8]) -> std::io::Result<usize> {
        self.io(|mut socket| socket.write(bytes))
    }
    fn flush(&mut self) -> std::io::Result<()> {
        self.io(|mut socket| socket.flush())
    }
}

fn write_frame(s: &mut impl Transport, data: &[u8]) -> Result<(), String> {
    if data.len() > 65535 {
        return Err("Oversized transport frame".into());
    }
    s.write_all(&(data.len() as u32).to_be_bytes())
        .map_err(err)?;
    s.write_all(data).map_err(err)
}
fn read_frame(s: &mut impl Transport, max: usize) -> Result<Vec<u8>, String> {
    let mut header = [0; 4];
    s.read_exact(&mut header).map_err(err)?;
    let n = u32::from_be_bytes(header) as usize;
    if n > max {
        return Err("Oversized transport frame".into());
    }
    let mut bytes = vec![0; n];
    s.read_exact(&mut bytes).map_err(err)?;
    Ok(bytes)
}
fn handshake(
    s: &mut impl Transport,
    key: &[u8; 32],
    initiator: bool,
) -> Result<snow::TransportState, String> {
    let prologue = format!("{DOMAIN}/sync/{VERSION}");
    let builder = snow::Builder::new(PATTERN.parse().map_err(err)?)
        .psk(0, key)
        .map_err(err)?
        .prologue(prologue.as_bytes())
        .map_err(err)?;
    let mut state = if initiator {
        builder.build_initiator()
    } else {
        builder.build_responder()
    }
    .map_err(err)?;
    let mut out = [0u8; 65535];
    if initiator {
        let n = state.write_message(&[], &mut out).map_err(err)?;
        write_frame(s, &out[..n])?;
        state
            .read_message(&read_frame(s, 1024)?, &mut out)
            .map_err(err)?;
    } else {
        state
            .read_message(&read_frame(s, 1024)?, &mut out)
            .map_err(err)?;
        let n = state.write_message(&[], &mut out).map_err(err)?;
        write_frame(s, &out[..n])?;
    }
    state.into_transport_mode().map_err(err)
}
fn send<T: Serialize>(
    s: &mut impl Transport,
    n: &mut snow::TransportState,
    value: &T,
) -> Result<(), String> {
    send_counted(s, n, value).map(|_| ())
}
fn send_counted<T: Serialize>(
    s: &mut impl Transport,
    n: &mut snow::TransportState,
    value: &T,
) -> Result<usize, String> {
    let bytes = serde_json::to_vec(value).map_err(err)?;
    if bytes.len() > MAX {
        return Err("Sync history exceeds transfer limit".into());
    }
    let mut out = [0; 65535];
    for part in bytes.chunks(60000) {
        let len = n.write_message(part, &mut out).map_err(err)?;
        write_frame(s, &out[..len])?;
    }
    let len = n.write_message(&[], &mut out).map_err(err)?;
    write_frame(s, &out[..len])?;
    Ok(bytes.len())
}
fn recv<T: for<'de> Deserialize<'de>>(
    s: &mut impl Transport,
    n: &mut snow::TransportState,
) -> Result<T, String> {
    recv_counted(s, n).map(|(value, _)| value)
}
fn recv_counted<T: for<'de> Deserialize<'de>>(
    s: &mut impl Transport,
    n: &mut snow::TransportState,
) -> Result<(T, usize), String> {
    let mut bytes = vec![];
    let mut out = [0; 65535];
    let start = Instant::now();
    loop {
        if start.elapsed() > Duration::from_secs(60) {
            return Err("Sync transfer timed out".into());
        }
        let len = n
            .read_message(&read_frame(s, 65535)?, &mut out)
            .map_err(err)?;
        if len == 0 {
            break;
        }
        if bytes.len() + len > MAX {
            return Err("Oversized sync transfer".into());
        }
        bytes.extend_from_slice(&out[..len]);
    }
    Ok((serde_json::from_slice(&bytes).map_err(err)?, bytes.len()))
}
fn recv_inventory(
    s: &mut impl Transport,
    n: &mut snow::TransportState,
) -> Result<(Inventory, usize), String> {
    let (value, bytes): (Value, usize) = recv_counted(s, n)?;
    if value["version"] != VERSION {
        return Err(VERSION_ERROR.into());
    }
    if let Some(error) = value["error"].as_str() {
        return Err(error.into());
    }
    let inventory: Inventory = serde_json::from_value(value).map_err(err)?;
    if inventory.summary.count > 100000
        || inventory.summary.digest.len() != 64
        || !inventory
            .summary
            .digest
            .bytes()
            .all(|b| b.is_ascii_digit() || (b'a'..=b'f').contains(&b))
    {
        return Err("Invalid sync inventory summary".into());
    }
    Ok((inventory, bytes))
}
fn check_summary(manifest: &sync_store::Manifest, expected: &Summary) -> Result<(), String> {
    if manifest.version != VERSION {
        return Err(VERSION_ERROR.into());
    }
    if summary(manifest)? != *expected {
        return Err("Sync inventory changed during transfer; retry".into());
    }
    Ok(())
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn encrypted_transport_round_trip() {
        let listener = TcpListener::bind("127.0.0.1:0").unwrap();
        let addr = listener.local_addr().unwrap();
        let server = std::thread::spawn(move || {
            let (mut s, _) = listener.accept().unwrap();
            let mut n = handshake(&mut s, &[7; 32], false).unwrap();
            let value: Value = recv(&mut s, &mut n).unwrap();
            send(&mut s, &mut n, &value).unwrap();
        });
        let mut s = TcpStream::connect(addr).unwrap();
        let mut n = handshake(&mut s, &[7; 32], true).unwrap();
        let value = json!({"recipe":"a".repeat(150000)});
        send(&mut s, &mut n, &value).unwrap();
        assert_eq!(recv::<Value>(&mut s, &mut n).unwrap(), value);
        server.join().unwrap();
    }
    #[test]
    fn wrong_secret_and_public_address_rejected() {
        let listener = TcpListener::bind("127.0.0.1:0").unwrap();
        let addr = listener.local_addr().unwrap();
        let server = std::thread::spawn(move || {
            let (mut s, _) = listener.accept().unwrap();
            assert!(handshake(&mut s, &[8; 32], false).is_err());
        });
        let mut s = TcpStream::connect(addr).unwrap();
        assert!(handshake(&mut s, &[7; 32], true).is_err());
        server.join().unwrap();
        assert!(endpoint("8.8.8.8:47831").is_err());
        assert!(endpoint(&format!("192.168.1.2:{PORT}")).is_ok());
    }
}

fn connect_error(target: SocketAddr, error: &std::io::Error) -> String {
    if error.kind() == std::io::ErrorKind::PermissionDenied {
        return format!(
            "Local network access denied for {target}. Allow Nearby devices for cookdex dev in Android app settings, then retry."
        );
    }
    format!(
        "Device unavailable. Address {target}: {error}. Keep Android apps in the foreground. Check the invitation's address and Windows private-network firewall access."
    )
}
fn transient_transfer(error: &str) -> bool {
    if error.contains("authenticating")
        || error.contains("identity")
        || error.contains("Incompatible")
    {
        return false;
    }
    let lower = error.to_lowercase();
    [
        "timed out",
        "timeout",
        "failed to fill whole buffer",
        "forcibly closed",
        "connection reset",
        "broken pipe",
        "connection aborted",
    ]
    .iter()
    .any(|text| lower.contains(text))
}
fn connection_error(stage: &str, detail: String, pairing: bool) -> String {
    let advice = if pairing {
        "Keep the source app open (Android in the foreground). Create a new invitation if the previous one was used or revoked."
    } else {
        "Keep both apps open (Android in the foreground). If this device was forgotten, pair it again with a new invitation."
    };
    let version_advice = if stage == "negotiating sync version" {
        VERSION_ERROR
    } else {
        ""
    };
    format!(
        "The exchange stopped while {stage}. {version_advice} {advice} Check the other device’s sync status for its reason. Details: {detail}"
    )
}

#[cfg(test)]
mod c9_security_tests {
    use super::*;
    #[test]
    fn connection_failures_identify_target_and_preserve_permission_reason() {
        let target = "192.168.1.7:47832".parse().unwrap();
        let denied = connect_error(target, &std::io::ErrorKind::PermissionDenied.into());
        assert!(denied.contains("Local network access denied"));
        assert!(denied.contains("192.168.1.7:47832"));
        assert!(denied.contains("Nearby devices"));
        let unavailable = connect_error(target, &std::io::ErrorKind::ConnectionRefused.into());
        assert!(unavailable.starts_with("Device unavailable. Address 192.168.1.7:47832:"));
        assert!(unavailable.contains("connection refused"));
        assert!(!unavailable.contains("pair again"));
    }
    fn service() -> Service {
        let s = Service::new(Arc::new(Mutex::new(
            storage::open(std::path::Path::new(":memory:")).unwrap(),
        )))
        .unwrap();
        s.active.store(true, Ordering::SeqCst);
        s.runtime.lock().unwrap().config.enabled = true;
        s
    }
    fn noise_pair(
        prologue_a: &[u8],
        prologue_b: &[u8],
    ) -> Result<(snow::TransportState, snow::TransportState), String> {
        let secret = [42; 32];
        let mut a = snow::Builder::new(PATTERN.parse().unwrap())
            .psk(0, &secret)
            .unwrap()
            .prologue(prologue_a)
            .unwrap()
            .build_initiator()
            .unwrap();
        let mut b = snow::Builder::new(PATTERN.parse().unwrap())
            .psk(0, &secret)
            .unwrap()
            .prologue(prologue_b)
            .unwrap()
            .build_responder()
            .unwrap();
        let mut bytes = [0; 1024];
        let mut clear = [0; 1024];
        let n = a.write_message(&[], &mut bytes).map_err(err)?;
        b.read_message(&bytes[..n], &mut clear).map_err(err)?;
        let n = b.write_message(&[], &mut bytes).map_err(err)?;
        a.read_message(&bytes[..n], &mut clear).map_err(err)?;
        Ok((
            a.into_transport_mode().map_err(err)?,
            b.into_transport_mode().map_err(err)?,
        ))
    }
    #[test]
    fn shipping_identity_and_port_are_isolated() {
        assert!(
            noise_pair(
                b"cookdex-flutter-development/1",
                b"cookdex-flutter-production/1"
            )
            .is_err()
        );
        if cfg!(feature = "production-sync") {
            assert_eq!(PORT, 47831);
            assert_eq!(DOMAIN, "cookdex-flutter-production/1");
            assert!(!valid_port(47832));
        } else {
            assert_eq!(PORT, 47832);
            assert_eq!(DOMAIN, "cookdex-flutter-development/1");
            assert!(!valid_port(47831));
        }
    }
    #[test]
    fn development_and_production_are_cryptographically_separate_from_tauri() {
        assert!(
            noise_pair(
                b"cookdex-flutter-development/1",
                b"cookdex-flutter-production/1"
            )
            .is_err()
        );
        assert!(noise_pair(DOMAIN.as_bytes(), b"my-recipe-book/lan-sync/1").is_err());
        if !cfg!(feature = "production-sync") {
            assert!(endpoint("127.0.0.1:47831").is_err());
            assert_eq!(PORT, 47832);
        }
        let s = service();
        let code = s.invitation("127.0.0.1".into()).unwrap();
        let mut invite: Invitation = serde_json::from_slice(
            &B64.decode(code.strip_prefix("recipe-pair:").unwrap())
                .unwrap(),
        )
        .unwrap();
        invite.domain = "foreign-domain".into();
        invite.id = Uuid::new_v4().to_string();
        let code = format!(
            "recipe-pair:{}",
            B64.encode(serde_json::to_vec(&invite).unwrap())
        );
        assert!(s.pair(code).is_err());
    }
    #[test]
    fn noise_rejects_tampering_and_replayed_ciphertext() {
        let (mut a, mut b) = noise_pair(DOMAIN.as_bytes(), DOMAIN.as_bytes()).unwrap();
        let mut cipher = [0; 1024];
        let mut clear = [0; 1024];
        let n = a.write_message(b"recipe revision", &mut cipher).unwrap();
        assert_eq!(b.read_message(&cipher[..n], &mut clear).unwrap(), 15);
        assert!(b.read_message(&cipher[..n], &mut clear).is_err());
        let (mut a, mut b) = noise_pair(DOMAIN.as_bytes(), DOMAIN.as_bytes()).unwrap();
        let n = a.write_message(b"recipe revision", &mut cipher).unwrap();
        cipher[n - 1] ^= 1;
        assert!(b.read_message(&cipher[..n], &mut clear).is_err());
    }
    #[test]
    fn invitation_replacement_disable_and_sixteen_peer_limit_revoke_trust() {
        let s = service();
        s.invitation("127.0.0.1".into()).unwrap();
        let old = s
            .runtime
            .lock()
            .unwrap()
            .pending
            .as_ref()
            .unwrap()
            .invite
            .clone();
        s.invitation("127.0.0.1".into()).unwrap();
        {
            let rt = s.runtime.lock().unwrap();
            assert!(
                s.check_incoming(&rt, &old.pair, "new-device", &key(&old.key).unwrap(), true)
                    .is_err()
            );
        }
        s.configure(false, "Device".into()).unwrap();
        assert!(s.runtime.lock().unwrap().pending.is_none());
        s.active.store(true, Ordering::SeqCst);
        {
            let mut rt = s.runtime.lock().unwrap();
            rt.config.enabled = true;
            for i in 0..16 {
                rt.config.peers.push(Peer {
                    id: format!("device-{i}"),
                    name: format!("Device {i}"),
                    address: format!("127.0.0.1:{PORT}"),
                    pair: Uuid::new_v4().to_string(),
                    key: B64.encode([i as u8; 32]),
                    last_sync: None,
                    acknowledged: None,
                });
            }
            let peer = Peer {
                id: "seventeenth".into(),
                name: "No room".into(),
                address: format!("127.0.0.1:{PORT}"),
                pair: Uuid::new_v4().to_string(),
                key: B64.encode([19; 32]),
                last_sync: None,
                acknowledged: None,
            };
            assert!(s.check_outgoing(&rt, &peer, false).is_err());
        }
        // Invitations may replace an existing identity at capacity; the
        // authenticated distinct-identity limit is enforced when staging.
        assert!(s.invitation("127.0.0.1".into()).is_ok());
    }
}

#[cfg(test)]
mod retry_tests {
    use super::*;
    fn service() -> Service {
        let service = Service::new(Arc::new(Mutex::new(
            storage::open(std::path::Path::new(":memory:")).unwrap(),
        )))
        .unwrap();
        service.active.store(true, Ordering::SeqCst);
        service
    }
    fn peer(id: &str) -> Peer {
        Peer {
            id: id.into(),
            name: id.into(),
            address: format!("127.0.0.1:{PORT}"),
            pair: id.into(),
            key: B64.encode([23; 32]),
            last_sync: None,
            acknowledged: None,
        }
    }
    #[test]
    fn unreadable_recipe_is_visible_and_automatic_retries_back_off() {
        let service = service();
        lock(&service.runtime)
            .unwrap()
            .config
            .peers
            .push(peer("fixture-peer"));
        let reports = service
            .sync_with_exchange(false, |_| Err(sync_store::RECIPE_ERROR.into()))
            .unwrap();
        assert_eq!(reports[0]["status"], "error");
        assert_eq!(reports[0]["error"], sync_store::RECIPE_ERROR);
        assert_eq!(reports[0]["retryAfterSeconds"], 60);
        let reports = service
            .sync_with_exchange(false, |_| panic!("must not retry before the deadline"))
            .unwrap();
        assert_eq!(reports[0]["error"], sync_store::RECIPE_ERROR);
        let reports = service.sync_with_exchange(true, |_| Ok(())).unwrap();
        assert_eq!(reports[0]["status"], "synced");
    }
    #[test]
    fn unavailable_backoff_doubles_then_caps_and_allows_due_or_manual_retry() {
        let service = service();
        let mut rt = lock(&service.runtime).unwrap();
        let unavailable = Err(connect_error(
            "192.168.1.7:47832".parse().unwrap(),
            &std::io::ErrorKind::ConnectionRefused.into(),
        ));
        let mut at = Instant::now();
        for seconds in [60, 120, 240, 300, 300] {
            rt.record_result("offline", &unavailable, at);
            assert_eq!(rt.retry_after("offline", false, at), Some(seconds));
            assert_eq!(rt.retry_after("offline", true, at), None);
            assert_eq!(rt.retry_after("healthy", false, at), None);
            assert_eq!(
                rt.retry_after("offline", false, at + Duration::from_secs(seconds - 1)),
                Some(1)
            );
            at += Duration::from_secs(seconds);
            assert_eq!(rt.retry_after("offline", false, at), None);
        }
        rt.record_result("offline", &Ok(()), at);
        assert_eq!(rt.retry_after("offline", false, at), None);
        rt.record_result("offline", &unavailable, at);
        assert_eq!(rt.retry_after("offline", false, at), Some(60));
        rt.record_result("offline", &Err("Authentication failed".into()), at);
        assert_eq!(rt.retry_after("offline", false, at), None);
    }
    #[test]
    fn automatic_sync_skips_waiting_peer_and_manual_sync_bypasses_retry() {
        let service = service();
        lock(&service.runtime).unwrap().config.peers = vec![peer("offline"), peer("healthy")];
        let mut calls = vec![];
        let reports = service
            .sync_with_exchange(false, |peer| {
                calls.push(peer.id.clone());
                if peer.id == "offline" {
                    Err(connect_error(
                        "192.168.1.7:47832".parse().unwrap(),
                        &std::io::ErrorKind::TimedOut.into(),
                    ))
                } else {
                    Ok(())
                }
            })
            .unwrap();
        assert_eq!(calls, ["offline", "healthy"]);
        assert_eq!(reports[0]["status"], "waiting");
        assert_eq!(reports[0]["error"], Value::Null);
        assert_eq!(reports[0]["retryAfterSeconds"], 60);
        calls.clear();
        let reports = service
            .sync_with_exchange(false, |peer| {
                calls.push(peer.id);
                Ok(())
            })
            .unwrap();
        assert_eq!(calls, ["healthy"]);
        assert_eq!(reports[0]["status"], "waiting");
        assert_eq!(reports[1]["status"], "synced");
        calls.clear();
        service
            .sync_with_exchange(true, |peer| {
                calls.push(peer.id);
                Ok(())
            })
            .unwrap();
        assert_eq!(calls, ["offline", "healthy"]);
        assert!(lock(&service.runtime).unwrap().retries.is_empty());
    }
    #[test]
    fn interrupted_transfer_retries_before_attention_and_forget_clears_report() {
        let service = service();
        lock(&service.runtime).unwrap().config.peers = vec![peer("phone")];
        let reason = "The exchange stopped while receiving recipe changes. Details: failed to fill whole buffer";
        for expected in ["waiting", "waiting", "error"] {
            let report = service
                .sync_with_exchange(true, |_| Err(reason.into()))
                .unwrap();
            assert_eq!(report[0]["status"], expected);
        }
        let report = service
            .sync_with_exchange(false, |_| panic!("backoff"))
            .unwrap();
        assert_eq!(report[0]["status"], "error");
        service.forget("phone").unwrap();
        assert!(
            service.status().unwrap()["reports"]
                .as_array()
                .unwrap()
                .is_empty()
        );
    }

    #[test]
    fn authentication_failure_stays_an_error_and_never_backs_off() {
        let service = service();
        lock(&service.runtime).unwrap().config.peers = vec![peer("wrong-secret")];
        let mut calls = 0;
        for _ in 0..2 {
            let reports = service
                .sync_with_exchange(false, |_| {
                    calls += 1;
                    Err("Authentication failed".into())
                })
                .unwrap();
            assert_eq!(reports[0]["status"], "error");
            assert_eq!(reports[0]["error"], "Authentication failed");
            assert_eq!(reports[0]["retryAfterSeconds"], Value::Null);
        }
        assert_eq!(calls, 2);
    }
    #[test]
    fn foreground_resume_resets_backoff_and_reuses_started_listeners() {
        let service = service();
        {
            let mut rt = lock(&service.runtime).unwrap();
            rt.config.enabled = true;
            // No bind is needed for this state-transition test. Once started,
            // foreground transitions must preserve the existing listener pair.
            rt.started = true;
            rt.config.peers = vec![peer("offline")];
            rt.record_result(
                "offline",
                &Err("Device unavailable.".into()),
                Instant::now(),
            );
        }
        service.foreground(true).unwrap();
        assert!(!lock(&service.runtime).unwrap().retries.is_empty());
        service.foreground(false).unwrap();
        assert!(!service.active.load(Ordering::SeqCst));
        service.foreground(true).unwrap();
        assert!(service.active.load(Ordering::SeqCst));
        assert!(lock(&service.runtime).unwrap().retries.is_empty());
        assert!(lock(&service.runtime).unwrap().started);
        let mut calls = 0;
        service
            .sync_with_exchange(false, |_| {
                calls += 1;
                Ok(())
            })
            .unwrap();
        assert_eq!(calls, 1);
    }
    #[test]
    fn forgetting_a_waiting_peer_discards_its_retry_state() {
        let service = service();
        {
            let mut rt = lock(&service.runtime).unwrap();
            rt.config.peers = vec![peer("offline")];
            rt.record_result(
                "offline",
                &Err("Device unavailable.".into()),
                Instant::now(),
            );
        }
        service.forget("offline").unwrap();
        assert!(lock(&service.runtime).unwrap().retries.is_empty());
    }
}

#[cfg(test)]
mod accepted_socket_tests {
    use super::*;
    #[test]
    fn idle_listeners_wait_for_packets_without_periodic_receive_timeouts() {
        let (listener, udp) = bind_listeners(0).unwrap();
        let port = listener.local_addr().unwrap().port();
        assert_eq!(udp.local_addr().unwrap().port(), port);
        assert_eq!(udp.read_timeout().unwrap(), None);
        let (accepted, acceptance) = std::sync::mpsc::channel();
        let tcp_worker = std::thread::spawn(move || {
            let (stream, _) = listener.accept().unwrap();
            accepted.send(()).unwrap();
            stream
        });
        let (received, reception) = std::sync::mpsc::channel();
        let udp_worker = std::thread::spawn(move || {
            let mut bytes = [0; 16];
            let (n, _) = udp.recv_from(&mut bytes).unwrap();
            received.send(bytes[..n].to_vec()).unwrap();
        });
        assert!(matches!(
            acceptance.try_recv(),
            Err(std::sync::mpsc::TryRecvError::Empty)
        ));
        assert!(matches!(
            reception.try_recv(),
            Err(std::sync::mpsc::TryRecvError::Empty)
        ));
        let _stream = TcpStream::connect((Ipv4Addr::LOCALHOST, port)).unwrap();
        let sender = UdpSocket::bind((Ipv4Addr::LOCALHOST, 0)).unwrap();
        sender
            .send_to(b"discovery", (Ipv4Addr::LOCALHOST, port))
            .unwrap();
        acceptance.recv_timeout(Duration::from_secs(3)).unwrap();
        assert_eq!(
            reception.recv_timeout(Duration::from_secs(3)).unwrap(),
            b"discovery"
        );
        tcp_worker.join().unwrap();
        udp_worker.join().unwrap();
    }
    #[test]
    fn delayed_handshake_on_nonblocking_accepted_socket() {
        let (a, b, peer) = super::incremental_tests::setup();
        let listener = TcpListener::bind((Ipv4Addr::LOCALHOST, 0)).unwrap();
        let addr = listener.local_addr().unwrap();
        let worker = std::thread::spawn(move || {
            let (socket, addr) = listener.accept().unwrap();
            socket.set_nonblocking(true).unwrap();
            std::thread::sleep(Duration::from_millis(100));
            b.receive(socket, addr)
        });
        a.exchange_at(peer, addr, true).unwrap();
        worker.join().unwrap().unwrap();
    }
}

#[cfg(test)]
mod incremental_tests {
    use super::*;
    fn service() -> Service {
        let s = Service::new(Arc::new(Mutex::new(
            storage::open(std::path::Path::new(":memory:")).unwrap(),
        )))
        .unwrap();
        s.active.store(true, Ordering::SeqCst);
        s
    }
    pub(super) fn setup() -> (Service, Service, Peer) {
        let (a, b) = (service(), service());
        let peer = Peer {
            id: b.id.clone(),
            name: "B".into(),
            address: format!("127.0.0.1:{PORT}"),
            pair: Uuid::new_v4().to_string(),
            key: B64.encode([32; 32]),
            last_sync: None,
            acknowledged: None,
        };
        lock(&b.runtime).unwrap().pending = Some(Pending {
            invite: Invitation {
                domain: DOMAIN.into(),
                version: VERSION,
                id: b.id.clone(),
                name: "B".into(),
                address: peer.address.clone(),
                alternatives: vec![],
                pair: peer.pair.clone(),
                key: peer.key.clone(),
            },
            expires: Instant::now() + Duration::from_secs(60),
        });
        lock(&a.runtime).unwrap().config.peers.push(peer.clone());
        let mut reverse = peer.clone();
        reverse.id = a.id.clone();
        reverse.name = "A".into();
        lock(&b.runtime).unwrap().config.peers.push(reverse);
        (a, b, peer)
    }
    fn listen(b: &Service) -> (SocketAddr, std::thread::JoinHandle<Result<(), String>>) {
        let listener = TcpListener::bind("127.0.0.1:0").unwrap();
        let addr = listener.local_addr().unwrap();
        let b = b.clone();
        let worker = std::thread::spawn(move || {
            let (s, addr) = listener.accept().unwrap();
            b.receive(s, addr)
        });
        (addr, worker)
    }
    fn exchange(a: &Service, b: &Service, peer: &Peer, known: bool) -> ExchangeStats {
        let (addr, worker) = listen(b);
        let stats = a.exchange_at_counted(peer.clone(), addr, known).unwrap();
        worker.join().unwrap().unwrap();
        stats
    }
    #[test]
    fn first_exchange_snapshots_both_sides_and_snapshot_failure_never_blocks_sync() {
        for blocked in [false, true] {
            let root =
                std::env::temp_dir().join(format!("cookdex-sync-snapshots-{}", Uuid::new_v4()));
            let (a, b, peer) = setup();
            let mut book: storage::Book =
                serde_json::from_str(include_str!("../tests/native-fixture.json")).unwrap();
            for (index, service) in [&a, &b].into_iter().enumerate() {
                let directory = root.join(index.to_string());
                std::fs::create_dir_all(&directory).unwrap();
                let mut conn = storage::open(&directory.join("cookdex.sqlite3")).unwrap();
                book.recipes[0]["id"] = json!(format!("recipe-{index}"));
                storage::save(&mut conn, 0, &book, "seed").unwrap();
                *service.db.lock().unwrap() = conn;
                if blocked {
                    std::fs::write(directory.join("snapshots"), b"unavailable").unwrap();
                }
            }
            exchange(&a, &b, &peer, true);
            for service in [&a, &b] {
                let mut db = service.db.lock().unwrap();
                assert_eq!(storage::load(&mut db).unwrap().book.recipes.len(), 2);
                if !blocked {
                    let entries = crate::rolling_snapshots::list(&db).unwrap();
                    assert_eq!(entries.len(), 1);
                    assert_eq!(entries[0].reason, "before_first_sync");
                    assert_eq!(entries[0].recipe_count, 1);
                }
            }
            // The second exchange must not replace the pre-sync archive.
            let peer = a.runtime.lock().unwrap().config.peers[0].clone();
            exchange(&a, &b, &peer, true);
            if !blocked {
                for service in [&a, &b] {
                    let db = service.db.lock().unwrap();
                    let entries = crate::rolling_snapshots::list(&db).unwrap();
                    assert_eq!(entries.len(), 1);
                    assert_eq!(entries[0].recipe_count, 1);
                }
            }
            drop(a);
            drop(b);
            std::fs::remove_dir_all(root).unwrap();
        }
    }
    #[test]
    fn pairing_tries_an_invited_lan_address_after_unreachable_virtual_adapter() {
        let (a, b, _) = setup();
        let (addr, worker) = listen(&b);
        let mut invite = lock(&b.runtime)
            .unwrap()
            .pending
            .as_ref()
            .unwrap()
            .invite
            .clone();
        invite.address = format!("127.0.0.2:{}", addr.port());
        invite.alternatives = vec![addr.to_string()];
        let code = format!(
            "recipe-pair:{}",
            B64.encode(serde_json::to_vec(&invite).unwrap())
        );
        a.pair(code).unwrap();
        worker.join().unwrap().unwrap();
        assert_eq!(
            lock(&a.runtime).unwrap().config.peers[0].address,
            addr.to_string()
        );
        assert_eq!(lock(&b.runtime).unwrap().config.peers[0].id, a.id);
    }
    #[test]
    fn invitation_alternatives_are_bounded_local_same_port_and_validate_before_mutation() {
        let (a, b, _) = setup();
        let mut invite = lock(&b.runtime)
            .unwrap()
            .pending
            .as_ref()
            .unwrap()
            .invite
            .clone();
        // Older Flutter invitations without alternatives remain valid.
        let mut old = serde_json::to_value(&invite).unwrap();
        old.as_object_mut().unwrap().remove("alternatives");
        assert_eq!(
            invitation_targets(&serde_json::from_value(old).unwrap())
                .unwrap()
                .len(),
            1
        );
        let generation = storage::load(&mut lock(&a.db).unwrap()).unwrap().generation;
        for invalid in [
            vec![format!("8.8.8.8:{PORT}")],
            vec!["127.0.0.1:47831".into()],
            vec![format!("127.0.0.1:{PORT}"); 8],
        ] {
            invite.alternatives = invalid;
            let code = format!(
                "recipe-pair:{}",
                B64.encode(serde_json::to_vec(&invite).unwrap())
            );
            assert!(a.pair(code).is_err());
            assert_eq!(lock(&a.runtime).unwrap().config.peers.len(), 1);
            assert_eq!(
                storage::load(&mut lock(&a.db).unwrap()).unwrap().generation,
                generation
            );
        }
    }
    fn connect(addr: SocketAddr, peer: &Peer) -> (TcpStream, snow::TransportState) {
        let mut s = TcpStream::connect(addr).unwrap();
        s.set_read_timeout(Some(Duration::from_secs(3))).unwrap();
        negotiate(&mut s, true).unwrap();
        write_frame(
            &mut s,
            &serde_json::to_vec(&Identification {
                pair: peer.pair.clone(),
                pairing: false,
            })
            .unwrap(),
        )
        .unwrap();
        let n = handshake(&mut s, &key(&peer.key).unwrap(), true).unwrap();
        (s, n)
    }
    fn start_inventory(
        s: &mut impl Transport,
        n: &mut snow::TransportState,
        a: &Service,
    ) -> Inventory {
        send(s, n, &a.identity().unwrap()).unwrap();
        let _: Identity = recv_small(s, n).unwrap();
        let snapshot = sync_store::export(&lock(&a.db).unwrap()).unwrap();
        send(
            s,
            n,
            &Inventory {
                port: PORT,
                version: VERSION,
                id: a.id.clone(),
                name: "A".into(),
                summary: summary(&sync_store::manifest(&snapshot).unwrap()).unwrap(),
            },
        )
        .unwrap();
        recv_inventory(s, n).unwrap().0
    }
    #[test]
    fn receipts_are_per_peer_persisted_and_include_remote_changes() {
        let (a, b, peer) = setup();
        let initial: storage::Book =
            serde_json::from_str(include_str!("../tests/native-fixture.json")).unwrap();
        storage::save(&mut lock(&a.db).unwrap(), 0, &initial, "first").unwrap();
        exchange(&a, &b, &peer, false);
        assert_eq!(a.status().unwrap()["peers"][0]["caughtUp"], true);
        assert_eq!(b.status().unwrap()["peers"][0]["caughtUp"], true);
        // A new local edit is pending despite a successful recent exchange.
        let mut db = lock(&a.db).unwrap();
        let mut state = storage::load(&mut db).unwrap();
        state.book.recipes[0]["notes"] = json!("new local change");
        storage::save(&mut db, state.generation, &state.book, "edit").unwrap();
        drop(db);
        assert_eq!(a.status().unwrap()["peers"][0]["caughtUp"], false);
        exchange(&a, &b, &peer, true);
        assert_eq!(a.status().unwrap()["peers"][0]["caughtUp"], true);
        // A third, offline peer must independently acknowledge the same history.
        let mut offline = peer.clone();
        offline.id = "offline-device".into();
        offline.acknowledged = None;
        lock(&a.runtime).unwrap().config.peers.push(offline);
        let peers = a.status().unwrap()["peers"].as_array().unwrap().clone();
        assert_eq!(peers.iter().filter(|p| p["caughtUp"] == true).count(), 1);
        assert_eq!(peers.iter().filter(|p| p["caughtUp"] == false).count(), 1);
        // Receipt survives reopening; legacy configs without a receipt remain unknown.
        let reopened = Service::new(a.db.clone()).unwrap();
        assert_eq!(reopened.status().unwrap()["peers"][0]["caughtUp"], true);
    }

    #[test]
    fn acknowledged_snapshot_never_includes_concurrent_or_third_device_events() {
        let (a, b, _) = setup();
        let local =
            sync_store::manifest(&sync_store::export(&lock(&a.db).unwrap()).unwrap()).unwrap();
        let remote =
            sync_store::manifest(&sync_store::export(&lock(&b.db).unwrap()).unwrap()).unwrap();
        let receipt = acknowledged_union(&local, &remote);
        let initial: storage::Book =
            serde_json::from_str(include_str!("../tests/native-fixture.json")).unwrap();
        storage::save(&mut lock(&a.db).unwrap(), 0, &initial, "concurrent edit").unwrap();
        assert_ne!(receipt, history_identity(&lock(&a.db).unwrap()).unwrap());
        // Never stamp the current DB at acknowledgement time.
        let after =
            sync_store::manifest(&sync_store::export(&lock(&a.db).unwrap()).unwrap()).unwrap();
        assert_ne!(receipt, acknowledged_union(&after, &remote));
    }

    #[test]
    fn real_tcp_noop_is_small_and_single_edits_transfer_only_new_revisions() {
        let (a, b, peer) = setup();
        let initial: storage::Book =
            serde_json::from_str(include_str!("../tests/native-fixture.json")).unwrap();
        storage::save(&mut lock(&a.db).unwrap(), 0, &initial, "first").unwrap();
        for i in 0..8 {
            let mut db = lock(&a.db).unwrap();
            let mut state = storage::load(&mut db).unwrap();
            state.book.recipes[0]["notes"] = json!(format!("edit {i}: {}", "x".repeat(19990)));
            storage::save(&mut db, state.generation, &state.book, "edit").unwrap();
        }
        let first = exchange(&a, &b, &peer, false);
        assert!(first.sent_events > 4);
        assert!(first.sent_bytes > 20000);
        let before_a = storage::load(&mut lock(&a.db).unwrap()).unwrap().generation;
        let before_b = storage::load(&mut lock(&b.db).unwrap()).unwrap().generation;
        let noop = exchange(&a, &b, &peer, true);
        assert_eq!((noop.sent_events, noop.received_events), (0, 0));
        assert!(noop.sent_bytes + noop.received_bytes < 1024);
        assert_eq!(
            storage::load(&mut lock(&a.db).unwrap()).unwrap().generation,
            before_a
        );
        assert_eq!(
            storage::load(&mut lock(&b.db).unwrap()).unwrap().generation,
            before_b
        );
        let mut db = lock(&a.db).unwrap();
        let mut state = storage::load(&mut db).unwrap();
        state.book.recipes[0]["notes"] = json!("single change");
        storage::save(&mut db, state.generation, &state.book, "edit").unwrap();
        drop(db);
        let changed = exchange(&a, &b, &peer, true);
        assert_eq!((changed.sent_events, changed.received_events), (1, 0));
        assert!(changed.sent_bytes < first.sent_bytes / 4);
        let mut db = lock(&b.db).unwrap();
        let mut state = storage::load(&mut db).unwrap();
        state.book.recipes[0]["notes"] = json!("reverse change");
        storage::save(&mut db, state.generation, &state.book, "edit").unwrap();
        drop(db);
        let reverse = exchange(&a, &b, &peer, true);
        assert_eq!((reverse.sent_events, reverse.received_events), (0, 1));
        assert_eq!(
            storage::load(&mut lock(&a.db).unwrap())
                .unwrap()
                .book
                .recipes,
            storage::load(&mut lock(&b.db).unwrap())
                .unwrap()
                .book
                .recipes
        );
    }
    #[test]
    fn interrupted_inventory_or_payload_preserves_data_and_invitation() {
        let (a, b, peer) = setup();
        for partial_packet in [false, true] {
            let (addr, worker) = listen(&b);
            let (mut s, mut n) = connect(addr, &peer);
            start_inventory(&mut s, &mut n, &a);
            if partial_packet {
                let mut out = [0; 65535];
                let len = n
                    .write_message(b"{\"version\":2,\"events\":[", &mut out)
                    .unwrap();
                write_frame(&mut s, &out[..len]).unwrap();
            }
            drop(s);
            assert!(worker.join().unwrap().is_err());
            assert_eq!(
                storage::load(&mut lock(&b.db).unwrap()).unwrap().generation,
                0
            );
            assert_eq!(lock(&b.runtime).unwrap().config.peers.len(), 1);
            assert!(lock(&b.runtime).unwrap().pending.is_some());
        }
        exchange(&a, &b, &peer, false);
    }
    #[test]
    fn revocation_after_inventory_prevents_payload_merge_and_peer_recreation() {
        let (a, b, peer) = setup();
        exchange(&a, &b, &peer, false);
        let before = storage::load(&mut lock(&b.db).unwrap()).unwrap().generation;
        let (addr, worker) = listen(&b);
        let (mut s, mut n) = connect(addr, &peer);
        start_inventory(&mut s, &mut n, &a);
        b.forget(&a.id).unwrap();
        send(
            &mut s,
            &mut n,
            &sync_store::Packet {
                version: VERSION,
                events: vec![],
            },
        )
        .unwrap();
        assert!(recv::<sync_store::Packet>(&mut s, &mut n).is_err());
        assert!(worker.join().unwrap().unwrap_err().contains("revoked"));
        assert_eq!(
            storage::load(&mut lock(&b.db).unwrap()).unwrap().generation,
            before
        );
        assert!(lock(&b.runtime).unwrap().config.peers.is_empty());
    }
}

#[cfg(test)]
mod session_shutdown_tests {
    use super::*;
    #[test]
    fn rejected_client_observes_eof_without_another_connection_or_shutdown() {
        let db = Arc::new(Mutex::new(
            storage::open(std::path::Path::new(":memory:")).unwrap(),
        ));
        let service = Service::new(db).unwrap();
        let listener = TcpListener::bind((Ipv4Addr::LOCALHOST, 0)).unwrap();
        let port = listener.local_addr().unwrap().port();
        service.listener_port.store(port, Ordering::SeqCst);
        service.active.store(true, Ordering::SeqCst);
        let server = service.clone();
        lock(&service.workers)
            .unwrap()
            .push(std::thread::spawn(move || server.listen(listener)));
        let mut client = TcpStream::connect((Ipv4Addr::LOCALHOST, port)).unwrap();
        client
            .set_read_timeout(Some(Duration::from_secs(2)))
            .unwrap();
        negotiate(&mut client, true).unwrap();
        write_frame(
            &mut client,
            &serde_json::to_vec(&Identification {
                pair: "not-a-pair".into(),
                pairing: false,
            })
            .unwrap(),
        )
        .unwrap();
        let result = client.read(&mut [0; 1]);
        service.shutdown(); // cleanup even if the assertion fails
        assert!(
            matches!(result, Ok(0))
                || result.is_err_and(|e| e.kind() == std::io::ErrorKind::ConnectionReset)
        );
    }

    #[test]
    fn shutdown_cancels_idle_accepted_client_and_releases_database() {
        let db = Arc::new(Mutex::new(
            storage::open(std::path::Path::new(":memory:")).unwrap(),
        ));
        let weak = Arc::downgrade(&db);
        let service = Service::new(db).unwrap();
        let listener = TcpListener::bind((Ipv4Addr::LOCALHOST, 0)).unwrap();
        let port = listener.local_addr().unwrap().port();
        service.listener_port.store(port, Ordering::SeqCst);
        service.active.store(true, Ordering::SeqCst);
        let server = service.clone();
        lock(&service.workers)
            .unwrap()
            .push(std::thread::spawn(move || server.listen(listener)));
        let _idle_client = TcpStream::connect((Ipv4Addr::LOCALHOST, port)).unwrap();
        let deadline = Instant::now() + Duration::from_secs(3);
        while lock(&service.receivers).unwrap().is_empty() {
            assert!(Instant::now() < deadline, "client never accepted");
            std::thread::sleep(Duration::from_millis(5));
        }
        let began = Instant::now();
        service.shutdown();
        assert!(
            began.elapsed() < Duration::from_secs(3),
            "shutdown waited for the 15s read timeout"
        );
        assert_eq!(service.inbound.load(Ordering::SeqCst), 0);
        drop(service);
        assert!(
            weak.upgrade().is_none(),
            "receiver retained database after shutdown"
        );
    }

    #[test]
    fn shutdown_wakes_and_joins_listeners_and_releases_database() {
        let db = Arc::new(Mutex::new(
            storage::open(std::path::Path::new(":memory:")).unwrap(),
        ));
        let weak = Arc::downgrade(&db);
        let service = Service::new(db).unwrap();
        let listener = TcpListener::bind((Ipv4Addr::LOCALHOST, 0)).unwrap();
        let port = listener.local_addr().unwrap().port();
        let udp = UdpSocket::bind((Ipv4Addr::LOCALHOST, port)).unwrap();
        service.listener_port.store(port, Ordering::SeqCst);
        let server = service.clone();
        lock(&service.workers)
            .unwrap()
            .push(std::thread::spawn(move || server.listen(listener)));
        let server = service.clone();
        lock(&service.workers)
            .unwrap()
            .push(std::thread::spawn(move || server.discover_listener(udp)));
        service.shutdown();
        service.shutdown(); // idempotent
        assert!(service.foreground(true).is_err());
        assert!(lock(&service.workers).unwrap().is_empty());
        drop(service);
        assert!(weak.upgrade().is_none());
        let _rebound = TcpListener::bind((Ipv4Addr::LOCALHOST, port)).unwrap();
    }
}

#[cfg(test)]
#[path = "lan_sync_security_tests.rs"]
mod security_v4_tests;
