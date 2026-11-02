//! bud-ffi: the vault of bud-core exposed to Swift over UniFFI (ADR-003 §2).
//!
//! This crate holds no logic: it turns core types into flat records and enums, core errors into
//! [`VaultError`], and keeps one [`bud_core::Vault`] behind a mutex so Swift can call it from any
//! thread.

use std::sync::{Arc, Mutex, MutexGuard};

uniffi::setup_scaffolding!("BudCore");

/// Every way a call into the vault can fail, with the core's message.
#[derive(Debug, thiserror::Error, uniffi::Error)]
pub enum VaultError {
    #[error("{message}")]
    Sqlite { message: String },
    #[error("{message}")]
    Io { message: String },
    #[error("{message}")]
    NotAFolder { message: String },
    #[error("{message}")]
    NoSuchBud { message: String },
    #[error("{message}")]
    Exists { message: String },
    #[error("{message}")]
    Invalid { message: String },
    #[error("{message}")]
    Watch { message: String },
}

impl From<bud_core::Error> for VaultError {
    fn from(error: bud_core::Error) -> Self {
        let message = error.to_string();
        match error {
            bud_core::Error::Sqlite(_) => VaultError::Sqlite { message },
            bud_core::Error::Io(_) => VaultError::Io { message },
            bud_core::Error::NotAFolder(_) => VaultError::NotAFolder { message },
            bud_core::Error::NoSuchBud(_) => VaultError::NoSuchBud { message },
            bud_core::Error::Exists(_) => VaultError::Exists { message },
            bud_core::Error::Invalid(_) => VaultError::Invalid { message },
            bud_core::Error::Watch(_) => VaultError::Watch { message },
        }
    }
}

type Result<T> = std::result::Result<T, VaultError>;

#[derive(Debug, Clone, Copy, PartialEq, Eq, uniffi::Enum)]
pub enum BudKind {
    Note,
    Todo,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, uniffi::Enum)]
pub enum BudState {
    Open,
    Done,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, uniffi::Enum)]
pub enum BudPlace {
    Everything,
    Inbox,
    Archive,
    Trash,
}

/// The lenses of the sidebar that are a plain list.
#[derive(Debug, Clone, Copy, PartialEq, Eq, uniffi::Enum)]
pub enum VaultLens {
    Todos,
    Pinned,
}

/// One bud as the folder has it, flat.
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct BudRecord {
    pub path: String,
    pub parent: Option<String>,
    pub title: String,
    pub kind: BudKind,
    pub state: Option<BudState>,
    pub when: Option<String>,
    pub due: Option<String>,
    pub pinned: bool,
    pub created: Option<String>,
    pub source: Option<String>,
    pub body: String,
    pub place: BudPlace,
}

/// A bud with the titles of the buds above it, root first.
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct RowRecord {
    pub bud: BudRecord,
    pub trail: Vec<String>,
}

/// A search result.
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct HitRecord {
    pub path: String,
    pub title: String,
    pub trail: Vec<String>,
    pub snippet: String,
}

/// What is under a bud: every descendant, and the open to-dos among them.
#[derive(Debug, Clone, Copy, PartialEq, Eq, uniffi::Record)]
pub struct CountsRecord {
    pub inside: u64,
    pub open_todos: u64,
}

/// Told once per batch of changes made outside the app, after the index has followed them.
/// `paths` are relative to the vault root and `/`-separated.
#[uniffi::export(callback_interface)]
pub trait VaultListener: Send + Sync {
    fn changed(&self, paths: Vec<String>);
}

struct Forward(Box<dyn VaultListener>);

impl bud_core::VaultListener for Forward {
    fn changed(&self, paths: Vec<String>) {
        self.0.changed(paths);
    }
}

/// A running watcher. It stops when this object is released or [`VaultWatch::stop`] is called.
#[derive(uniffi::Object)]
pub struct VaultWatch {
    watch: Mutex<Option<bud_core::Watch>>,
}

#[uniffi::export]
impl VaultWatch {
    pub fn stop(&self) {
        self.watch
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner())
            .take();
    }
}

/// How a node reaches peers that are not on the same network.
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Enum)]
pub enum RelaySetting {
    /// The public relays.
    Default,
    /// A relay of the person's own.
    Custom { url: String },
    /// No relay: direct connections only.
    Off,
}

impl From<RelaySetting> for bud_core::Relay {
    fn from(setting: RelaySetting) -> Self {
        match setting {
            RelaySetting::Default => bud_core::Relay::Default,
            RelaySetting::Custom { url } => bud_core::Relay::Custom(url),
            RelaySetting::Off => bud_core::Relay::Off,
        }
    }
}

impl From<bud_core::Relay> for RelaySetting {
    fn from(relay: bud_core::Relay) -> Self {
        match relay {
            bud_core::Relay::Default => RelaySetting::Default,
            bud_core::Relay::Custom(url) => RelaySetting::Custom { url },
            bud_core::Relay::Off => RelaySetting::Off,
        }
    }
}

/// A peer the vault remembers. `last_seen` is seconds since the epoch, none before the first
/// session.
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct PeerRecord {
    pub id: String,
    pub relay: RelaySetting,
    pub last_seen: Option<u64>,
}

impl From<bud_core::PeerInfo> for PeerRecord {
    fn from(peer: bud_core::PeerInfo) -> Self {
        PeerRecord {
            id: peer.id,
            relay: peer.relay.into(),
            last_seen: peer.last_seen.and_then(|seen| u64::try_from(seen).ok()),
        }
    }
}

/// What a node is doing: `idle` is true when no sync is running.
#[derive(Debug, Clone, Copy, PartialEq, Eq, uniffi::Record)]
pub struct SyncState {
    pub idle: bool,
    pub connected_peers: u64,
    pub pending_changes: u64,
}

/// What one sync did.
#[derive(Debug, Clone, Copy, PartialEq, Eq, uniffi::Record)]
pub struct SyncSummary {
    pub created: u64,
    pub updated: u64,
    pub written: u64,
    pub moved: u64,
    pub ops: u64,
}

impl From<bud_core::SyncReport> for SyncSummary {
    fn from(report: bud_core::SyncReport) -> Self {
        SyncSummary {
            created: report.created as u64,
            updated: report.updated as u64,
            written: report.written as u64,
            moved: report.moved as u64,
            ops: report.ops as u64,
        }
    }
}

/// A running peer node for one open vault. It stops when [`PeerNode::stop`] is called or this
/// object is released.
#[derive(uniffi::Object)]
pub struct PeerNode {
    node: Mutex<Option<bud_core::Node>>,
}

impl PeerNode {
    fn with<T>(&self, call: impl FnOnce(&bud_core::Node) -> bud_core::Result<T>) -> Result<T> {
        let guard = self
            .node
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner());
        match guard.as_ref() {
            Some(node) => Ok(call(node)?),
            None => Err(bud_core::Error::Invalid("peer: the node is closed".to_string()).into()),
        }
    }
}

#[uniffi::export]
impl PeerNode {
    /// Stop the node. Every later call on it fails.
    pub fn stop(&self) {
        self.node
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner())
            .take();
    }

    /// This node's id.
    pub fn id(&self) -> Result<String> {
        self.with(|node| Ok(node.id()))
    }

    /// A pairing ticket as a string. With `with_addresses` it carries the addresses the node
    /// listens on, for a peer that cannot look the node up.
    pub fn ticket(&self, with_addresses: bool) -> Result<String> {
        self.with(|node| Ok(Self::ticket_of(node, with_addresses)?.encode()))
    }

    /// The same ticket as the modules of a QR code, row by row; `true` is dark.
    pub fn ticket_qr(&self, with_addresses: bool) -> Result<Vec<Vec<bool>>> {
        self.with(|node| {
            let qr = Self::ticket_of(node, with_addresses)?.qr()?;
            Ok(qr
                .dark
                .chunks(qr.width.max(1))
                .map(<[bool]>::to_vec)
                .collect())
        })
    }

    /// Pair with the vault that made `ticket`.
    pub fn accept_ticket(&self, ticket: String) -> Result<PeerRecord> {
        self.with(|node| Ok(node.accept_ticket(&ticket)?.into()))
    }

    pub fn peers(&self) -> Result<Vec<PeerRecord>> {
        self.with(|node| Ok(node.peers()?.into_iter().map(Into::into).collect()))
    }

    pub fn forget_peer(&self, id: String) -> Result<()> {
        self.with(|node| node.forget_peer(&id))
    }

    /// Look at the folder, exchange changes with every peer and wait for it.
    pub fn sync_now(&self) -> Result<SyncSummary> {
        self.with(|node| Ok(node.sync_now()?.into()))
    }

    pub fn state(&self) -> Result<SyncState> {
        self.with(|node| {
            let state = node.state()?;
            Ok(SyncState {
                idle: !state.syncing,
                connected_peers: state.connected as u64,
                pending_changes: state.pending as u64,
            })
        })
    }
}

impl PeerNode {
    fn ticket_of(
        node: &bud_core::Node,
        with_addresses: bool,
    ) -> bud_core::Result<bud_core::Ticket> {
        if with_addresses {
            node.ticket_with_addresses()
        } else {
            node.ticket()
        }
    }
}

/// The vault of bud-core behind a mutex.
#[derive(uniffi::Object)]
pub struct Vault {
    inner: Arc<Mutex<bud_core::Vault>>,
}

/// Open the vault at `vault_dir` with its index at `index_path`, and bring the index up to date.
#[uniffi::export]
pub fn open_vault(vault_dir: String, index_path: String) -> Result<Arc<Vault>> {
    let mut vault = bud_core::Vault::open(vault_dir, index_path)?;
    vault.rescan()?;
    Ok(Arc::new(Vault {
        inner: Arc::new(Mutex::new(vault)),
    }))
}

/// Start a peer node for `vault`: it finds peers on the local network, syncs with them every few
/// seconds and answers the ones that sync with it.
#[uniffi::export]
pub fn start_node(vault: Arc<Vault>, relay: RelaySetting) -> Result<Arc<PeerNode>> {
    let node = bud_core::Node::start(Arc::clone(&vault.inner), relay.into())?;
    Ok(Arc::new(PeerNode {
        node: Mutex::new(Some(node)),
    }))
}

impl Vault {
    fn core(&self) -> MutexGuard<'_, bud_core::Vault> {
        self.inner
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner())
    }
}

#[uniffi::export]
impl Vault {
    /// Every bud in the index, parents before children.
    pub fn snapshot(&self) -> Result<Vec<BudRecord>> {
        Ok(self.core().all()?.into_iter().map(Into::into).collect())
    }

    pub fn children(&self, path: String) -> Result<Vec<BudRecord>> {
        Ok(self
            .core()
            .children(&path)?
            .into_iter()
            .map(Into::into)
            .collect())
    }

    pub fn bud(&self, path: String) -> Result<Option<BudRecord>> {
        Ok(self.core().bud(&path)?.map(Into::into))
    }

    /// Returns the new bud's path.
    pub fn create(
        &self,
        parent: Option<String>,
        title: String,
        kind: BudKind,
        source: Option<String>,
    ) -> Result<String> {
        Ok(self
            .core()
            .create(parent.as_deref(), &title, kind.into(), source.as_deref())?)
    }

    pub fn set_body(&self, path: String, text: String) -> Result<()> {
        Ok(self.core().set_body(&path, &text)?)
    }

    pub fn set_state(&self, path: String, state: BudState) -> Result<()> {
        Ok(self.core().set_state(&path, state.into())?)
    }

    pub fn set_pinned(&self, path: String, pinned: bool) -> Result<()> {
        Ok(self.core().set_pinned(&path, pinned)?)
    }

    /// Returns the new path.
    pub fn rename(&self, path: String, new_title: String) -> Result<String> {
        Ok(self.core().rename(&path, &new_title)?)
    }

    /// Returns the new path.
    pub fn move_to(&self, path: String, new_parent: Option<String>) -> Result<String> {
        Ok(self.core().move_to(&path, new_parent.as_deref())?)
    }

    pub fn trash(&self, path: String) -> Result<()> {
        Ok(self.core().trash(&path)?)
    }

    /// Returns the restored path.
    pub fn restore(&self, path: String) -> Result<String> {
        Ok(self.core().restore(&path)?)
    }

    pub fn search(&self, query: String, limit: u64) -> Result<Vec<HitRecord>> {
        let limit = usize::try_from(limit).unwrap_or(usize::MAX);
        Ok(self
            .core()
            .search(&query, limit)?
            .into_iter()
            .map(Into::into)
            .collect())
    }

    /// The open to-dos for `date` (`YYYY-MM-DD`).
    pub fn today(&self, date: String) -> Result<Vec<RowRecord>> {
        Ok(self
            .core()
            .today(&date)?
            .into_iter()
            .map(Into::into)
            .collect())
    }

    pub fn counts(&self, path: String) -> Result<CountsRecord> {
        Ok(self.core().counts(&path)?.into())
    }

    pub fn next_step(&self, under: Option<String>, date: String) -> Result<Option<RowRecord>> {
        Ok(self
            .core()
            .next_step(under.as_deref(), &date)?
            .map(Into::into))
    }

    pub fn lens(&self, lens: VaultLens) -> Result<Vec<RowRecord>> {
        Ok(self
            .core()
            .lens(lens.into())?
            .into_iter()
            .map(Into::into)
            .collect())
    }

    /// Follow the folder and tell `listener` once per batch of outside changes.
    pub fn watch(&self, listener: Box<dyn VaultListener>) -> Result<Arc<VaultWatch>> {
        let watch = self.core().watch(Box::new(Forward(listener)))?;
        Ok(Arc::new(VaultWatch {
            watch: Mutex::new(Some(watch)),
        }))
    }
}

impl From<BudKind> for bud_core::Kind {
    fn from(kind: BudKind) -> Self {
        match kind {
            BudKind::Note => bud_core::Kind::Note,
            BudKind::Todo => bud_core::Kind::Todo,
        }
    }
}

impl From<bud_core::Kind> for BudKind {
    fn from(kind: bud_core::Kind) -> Self {
        match kind {
            bud_core::Kind::Note => BudKind::Note,
            bud_core::Kind::Todo => BudKind::Todo,
        }
    }
}

impl From<BudState> for bud_core::State {
    fn from(state: BudState) -> Self {
        match state {
            BudState::Open => bud_core::State::Open,
            BudState::Done => bud_core::State::Done,
        }
    }
}

impl From<bud_core::State> for BudState {
    fn from(state: bud_core::State) -> Self {
        match state {
            bud_core::State::Open => BudState::Open,
            bud_core::State::Done => BudState::Done,
        }
    }
}

impl From<bud_core::Place> for BudPlace {
    fn from(place: bud_core::Place) -> Self {
        match place {
            bud_core::Place::Everything => BudPlace::Everything,
            bud_core::Place::Inbox => BudPlace::Inbox,
            bud_core::Place::Archive => BudPlace::Archive,
            bud_core::Place::Trash => BudPlace::Trash,
        }
    }
}

impl From<VaultLens> for bud_core::Lens {
    fn from(lens: VaultLens) -> Self {
        match lens {
            VaultLens::Todos => bud_core::Lens::Todos,
            VaultLens::Pinned => bud_core::Lens::Pinned,
        }
    }
}

impl From<bud_core::Bud> for BudRecord {
    fn from(bud: bud_core::Bud) -> Self {
        BudRecord {
            path: bud.path,
            parent: bud.parent,
            title: bud.title,
            kind: bud.kind.into(),
            state: bud.state.map(Into::into),
            when: bud.when,
            due: bud.due,
            pinned: bud.pinned,
            created: bud.created,
            source: bud.source,
            body: bud.body,
            place: bud.place.into(),
        }
    }
}

impl From<bud_core::Row> for RowRecord {
    fn from(row: bud_core::Row) -> Self {
        RowRecord {
            bud: row.bud.into(),
            trail: row.trail,
        }
    }
}

impl From<bud_core::Hit> for HitRecord {
    fn from(hit: bud_core::Hit) -> Self {
        HitRecord {
            path: hit.path,
            title: hit.title,
            trail: hit.trail,
            snippet: hit.snippet,
        }
    }
}

impl From<bud_core::Counts> for CountsRecord {
    fn from(counts: bud_core::Counts) -> Self {
        CountsRecord {
            inside: counts.inside as u64,
            open_todos: counts.open_todos as u64,
        }
    }
}
