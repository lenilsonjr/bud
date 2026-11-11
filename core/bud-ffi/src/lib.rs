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
    Warehouse,
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
    /// Where a planted bud came from, as in `mail:M1234`.
    pub from: Option<String>,
    /// How a planted bud stands with its source, as in `moved 2026-11-05T21:00:00Z`.
    pub from_state: Option<String>,
    pub body: String,
    pub place: BudPlace,
    /// The tags of its frontmatter list; the `#tags` in its body are read from the body.
    pub tags: Vec<String>,
}

/// Where a planted item went, and whether planting made that bud or found it.
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct PlantRecord {
    pub path: String,
    pub new: bool,
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

/// One entry of a map the vault keeps beside the buds: a source's settings or a lease.
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct SharedEntry {
    pub key: String,
    pub value: String,
}

/// A `[[link]]` written in a bud: the target as written, its label, and the bud it names when
/// exactly one does.
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct LinkRecord {
    pub from: String,
    pub target: String,
    pub label: Option<String>,
    pub to: Option<String>,
}

/// A picture file in the vault: its path, its file name, its size in bytes and its modification
/// time in seconds since the epoch.
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct AttachmentRecord {
    pub path: String,
    pub name: String,
    pub size: u64,
    pub mtime: i64,
}

/// An embed (`![[photo.png]]` or `![alt](photo.png)`) written in a bud: the file as written, its
/// label, and the attachment it names when exactly one does.
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct EmbedRecord {
    pub from: String,
    pub target: String,
    pub label: Option<String>,
    pub to: Option<String>,
}

/// A tag and how many buds carry it.
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct TagCountRecord {
    pub tag: String,
    pub buds: u64,
}

/// One file a tag change rewrote, with its text before and after.
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct TagEditRecord {
    pub path: String,
    pub before: String,
    pub after: String,
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
    /// The last key rotation could not move this peer: it holds the old key.
    pub missed: bool,
    /// What the peer said it is in its last session: `mac`, `iphone`, `ipad` or `tv`.
    pub kind: Option<String>,
    /// The name the peer's system gives it, as the peer sent it.
    pub name: Option<String>,
    /// The label this vault gave the peer, preferred over `name` when shown.
    pub label: Option<String>,
}

impl From<bud_core::PeerInfo> for PeerRecord {
    fn from(peer: bud_core::PeerInfo) -> Self {
        PeerRecord {
            id: peer.id,
            relay: peer.relay.into(),
            last_seen: peer.last_seen.and_then(|seen| u64::try_from(seen).ok()),
            missed: peer.missed,
            kind: peer.kind,
            name: peer.name,
            label: peer.label,
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

/// What a device without the vault shows to be let in: the code for the device with the vault to
/// scan, and the six words both sides show for the person to confirm.
#[derive(Clone, PartialEq, Eq, uniffi::Record)]
pub struct JoinCode {
    pub code: String,
    pub words: Vec<String>,
}

/// What a node tells as it goes, for the screens that show pairing and syncing.
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Enum)]
pub enum PeerEvent {
    /// A node redeemed a ticket this vault issued.
    TicketRedeemed { by: String },
    /// A node this vault did not know is now a peer.
    PeerJoined { id: String },
    /// A node that holds a vault brought its key to the join request this node shows: the words
    /// of that request and what the node says it is. The key is kept only once `answer_join`
    /// says so.
    JoinOffered {
        id: String,
        kind: Option<String>,
        name: Option<String>,
        words: Vec<String>,
    },
    /// One peer's part of a key rotation: `confirmed` when it took the new key in the hand over,
    /// else `holds_key` says what a probe found.
    KeyRotation {
        id: String,
        confirmed: bool,
        holds_key: bool,
    },
    /// The rotation is over, with the ids of the peers that still hold the old key.
    RotationDone { reached: u64, missed: Vec<String> },
    /// A first fetch from a peer: how many documents arrived, and how many buds the peer holds
    /// when it said.
    FetchProgress { received: u64, total: Option<u64> },
    /// A peer's changes were applied here in one session and changed buds, in files the watcher
    /// does not report: what they did. Told as soon as they are applied.
    SyncFinished { summary: SyncSummary },
    /// What this vault keeps of its pairing changed with no call on this node: a peer handed
    /// over a new vault key, or the accepted ticket was spent.
    PairingChanged,
}

impl From<bud_core::NodeEvent> for PeerEvent {
    fn from(event: bud_core::NodeEvent) -> Self {
        use bud_core::{NodeEvent, RotationOutcome};
        match event {
            NodeEvent::TicketRedeemed { by } => PeerEvent::TicketRedeemed { by },
            NodeEvent::PeerJoined { id } => PeerEvent::PeerJoined { id },
            NodeEvent::JoinOffered {
                id,
                kind,
                name,
                words,
            } => PeerEvent::JoinOffered {
                id,
                kind,
                name,
                words,
            },
            NodeEvent::KeyRotation { id, outcome } => {
                let (confirmed, holds_key) = match outcome {
                    RotationOutcome::Confirmed => (true, true),
                    RotationOutcome::Probed { holds_key } => (false, holds_key),
                };
                PeerEvent::KeyRotation {
                    id,
                    confirmed,
                    holds_key,
                }
            }
            NodeEvent::RotationDone(report) => PeerEvent::RotationDone {
                reached: report.reached as u64,
                missed: report.missed,
            },
            NodeEvent::FetchProgress { received, total } => PeerEvent::FetchProgress {
                received: received as u64,
                total: total.map(|n| n as u64),
            },
            NodeEvent::SyncFinished(report) => PeerEvent::SyncFinished {
                summary: report.into(),
            },
            NodeEvent::PairingChanged => PeerEvent::PairingChanged,
        }
    }
}

/// Told each [`PeerEvent`] as it happens, on the node's own threads or the thread of a call such
/// as `sync_now`, while the node holds its locks: a listener hands the event to another queue
/// and never calls the `PeerNode` synchronously, or it waits forever.
#[uniffi::export(callback_interface)]
pub trait PeerListener: Send + Sync {
    fn event(&self, event: PeerEvent);
}

struct ForwardEvents(Box<dyn PeerListener>);

impl bud_core::NodeListener for ForwardEvents {
    fn event(&self, event: bud_core::NodeEvent) {
        self.0.event(event.into());
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
        self.with(|node| Ok(Self::rows(Self::ticket_of(node, with_addresses)?.qr()?)))
    }

    /// Pair with the vault that made `ticket`.
    pub fn accept_ticket(&self, ticket: String) -> Result<PeerRecord> {
        self.with(|node| Ok(node.accept_ticket(&ticket)?.into()))
    }

    /// Show a join request, for a device that holds the vault to scan: it replaces the one shown
    /// before, lasts as long as a ticket, and is good once. The words are the request's
    /// fingerprint; the device that scans it shows the same six.
    pub fn join_request(&self) -> Result<JoinCode> {
        self.with(|node| {
            let request = node.join_request()?;
            Ok(JoinCode {
                code: request.encode(),
                words: request.words().to_vec(),
            })
        })
    }

    /// A join request's code as the modules of a QR code, row by row; `true` is dark.
    pub fn join_request_qr(&self, code: String) -> Result<Vec<Vec<bool>>> {
        self.with(|_| Ok(Self::rows(bud_core::JoinRequest::parse(&code)?.qr()?)))
    }

    /// Read a request another device shows: its six words, for the person to confirm against
    /// the device's. Nothing moves until `confirm_request`. A request of this vault's own, or one
    /// past its lifetime, is refused.
    pub fn read_request(&self, code: String) -> Result<Vec<String>> {
        self.with(|node| Ok(node.read_request(&code)?.words().to_vec()))
    }

    /// The person confirmed the words: bring this vault's key to the device that showed the
    /// request, and remember it as a peer.
    pub fn confirm_request(&self, code: String) -> Result<PeerRecord> {
        self.with(|node| {
            let request = node.read_request(&code)?;
            Ok(node.confirm_request(&request)?.into())
        })
    }

    /// The person answered the key on offer, told by `JoinOffered`: `keep` takes it and makes
    /// the device that brought it a peer; otherwise it is turned away and the request stays on
    /// show.
    pub fn answer_join(&self, keep: bool) -> Result<()> {
        self.with(|node| node.answer_join(keep))
    }

    pub fn peers(&self) -> Result<Vec<PeerRecord>> {
        self.with(|node| Ok(node.peers()?.into_iter().map(Into::into).collect()))
    }

    pub fn forget_peer(&self, id: String) -> Result<()> {
        self.with(|node| node.forget_peer(&id))
    }

    /// Lift the refusal of a node this vault removed, so it can redeem a new ticket.
    pub fn allow_peer(&self, id: String) -> Result<()> {
        self.with(|node| node.allow_peer(&id))
    }

    /// Hear every [`PeerEvent`] from now on, until the node stops. The listener must not call
    /// this node synchronously; see [`PeerListener`].
    pub fn listen(&self, listener: Box<dyn PeerListener>) -> Result<()> {
        self.with(|node| {
            node.listen(Box::new(ForwardEvents(listener)));
            Ok(())
        })
    }

    /// Give a peer a label of this vault's own, shown instead of the name it sends; none or an
    /// empty one takes it away.
    pub fn rename_peer(&self, id: String, label: Option<String>) -> Result<()> {
        self.with(|node| node.rename_peer(&id, label.as_deref()))
    }

    /// Make a new vault key and give it to every peer. Returns the ids of the peers it could not
    /// reach and that still hold the old key, and are turned away. `peers` marks them as `missed`.
    pub fn rotate_key(&self) -> Result<Vec<String>> {
        self.with(|node| Ok(node.rotate_key()?.missed))
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
    fn rows(qr: bud_core::Qr) -> Vec<Vec<bool>> {
        qr.dark
            .chunks(qr.width.max(1))
            .map(<[bool]>::to_vec)
            .collect()
    }

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
/// How long one session with a peer may take, in seconds, before it is given up.
#[uniffi::export]
pub fn session_timeout_seconds() -> u64 {
    bud_core::SESSION_TIMEOUT.as_secs()
}

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
    start_node_as(vault, relay, None, None)
}

/// Start a peer node that tells its peers what it is: its kind (`mac`, `iphone`, `ipad`, `tv`)
/// and the name its system gives it, both optional.
#[uniffi::export]
pub fn start_node_as(
    vault: Arc<Vault>,
    relay: RelaySetting,
    kind: Option<String>,
    name: Option<String>,
) -> Result<Arc<PeerNode>> {
    let options =
        bud_core::NodeOptions::new(relay.into()).with_identity(bud_core::Identity { kind, name });
    let node = bud_core::Node::start_with(Arc::clone(&vault.inner), options)?;
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
    /// This device's pairing, to keep outside a cache that may be cleared; none while it has no
    /// peer.
    pub fn pairing(&self) -> Result<Option<Vec<u8>>> {
        Ok(self.core().pairing()?)
    }

    /// Brings a kept pairing back, before a node starts on the vault. False, changing nothing,
    /// when the vault does not take it (`takes_pairing`).
    pub fn restore_pairing(&self, pairing: Vec<u8>) -> Result<bool> {
        Ok(self.core().restore_pairing(&pairing)?)
    }

    /// Whether `restore_pairing` would bring the kept pairing in: the vault has no node key and
    /// no peer of its own, or has the kept key and no peer.
    pub fn takes_pairing(&self, pairing: Vec<u8>) -> Result<bool> {
        Ok(self.core().takes_pairing(&pairing)?)
    }

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

    /// Plants a source item under `parent`, or finds the bud it was planted as before.
    pub fn plant(
        &self,
        parent: Option<String>,
        title: String,
        kind: BudKind,
        from: String,
    ) -> Result<PlantRecord> {
        let (path, new) = self
            .core()
            .plant(parent.as_deref(), &title, kind.into(), &from)?;
        Ok(PlantRecord { path, new })
    }

    /// The bud planted from a source item, by its `from:` key.
    pub fn planted(&self, from: String) -> Result<Option<BudRecord>> {
        Ok(self.core().planted(&from)?.map(Into::into))
    }

    pub fn set_body(&self, path: String, text: String) -> Result<()> {
        Ok(self.core().set_body(&path, &text)?)
    }

    /// The bud's file as it is on disk; a bud that is only a folder has none yet.
    pub fn text(&self, path: String) -> Result<String> {
        Ok(self.core().text(&path)?)
    }

    /// None removes the state and makes the bud a note.
    pub fn set_state(&self, path: String, state: Option<BudState>) -> Result<()> {
        Ok(self.core().set_state(&path, state.map(Into::into))?)
    }

    pub fn set_pinned(&self, path: String, pinned: bool) -> Result<()> {
        Ok(self.core().set_pinned(&path, pinned)?)
    }

    /// The day to do the bud (`YYYY-MM-DD`); none clears it.
    pub fn set_when(&self, path: String, when: Option<String>) -> Result<()> {
        Ok(self.core().set_when(&path, when.as_deref())?)
    }

    /// The day the bud is due (`YYYY-MM-DD`); none clears it.
    pub fn set_due(&self, path: String, due: Option<String>) -> Result<()> {
        Ok(self.core().set_due(&path, due.as_deref())?)
    }

    /// The settings of each connected source, synced with the vault and never holding a token.
    pub fn sources(&self) -> Result<Vec<SharedEntry>> {
        Ok(entries(self.core().sources()?))
    }

    pub fn set_source(&self, id: String, settings: Option<String>) -> Result<()> {
        Ok(self.core().set_source(&id, settings.as_deref())?)
    }

    /// Which device keeps each account's planted buds live.
    pub fn leases(&self) -> Result<Vec<SharedEntry>> {
        Ok(entries(self.core().leases()?))
    }

    pub fn set_lease(&self, id: String, lease: Option<String>) -> Result<()> {
        Ok(self.core().set_lease(&id, lease.as_deref())?)
    }

    /// The Library's triggers, synced with the vault.
    pub fn triggers(&self) -> Result<Vec<SharedEntry>> {
        Ok(entries(self.core().triggers()?))
    }

    pub fn set_trigger(&self, id: String, trigger: Option<String>) -> Result<()> {
        Ok(self.core().set_trigger(&id, trigger.as_deref())?)
    }

    /// How the panels around a page are arranged, synced with the vault.
    pub fn layout(&self) -> Result<Vec<SharedEntry>> {
        Ok(entries(self.core().layout()?))
    }

    pub fn set_layout(&self, key: String, layout: Option<String>) -> Result<()> {
        Ok(self.core().set_layout(&key, layout.as_deref())?)
    }

    /// Which tag columns each bud's board shows, synced with the vault.
    pub fn board(&self) -> Result<Vec<SharedEntry>> {
        Ok(entries(self.core().board()?))
    }

    pub fn set_board(&self, key: String, columns: Option<String>) -> Result<()> {
        Ok(self.core().set_board(&key, columns.as_deref())?)
    }

    /// The lenses the person named and kept, synced with the vault.
    pub fn lenses(&self) -> Result<Vec<SharedEntry>> {
        Ok(entries(self.core().lenses()?))
    }

    pub fn set_lens(&self, id: String, lens: Option<String>) -> Result<()> {
        Ok(self.core().set_lens(&id, lens.as_deref())?)
    }

    /// How a planted bud stands with its source; none clears it.
    pub fn set_from_state(&self, path: String, state: Option<String>) -> Result<()> {
        Ok(self.core().set_from_state(&path, state.as_deref())?)
    }

    /// When the bud was first made (an ISO moment), for a bud brought in from elsewhere; none
    /// clears it.
    pub fn set_created(&self, path: String, created: Option<String>) -> Result<()> {
        Ok(self.core().set_created(&path, created.as_deref())?)
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

    /// Remove a bud in the Trash and its branch for good; a bud elsewhere is refused.
    pub fn delete_forever(&self, path: String) -> Result<()> {
        Ok(self.core().delete_forever(&path)?)
    }

    /// Remove every bud in the Trash for good.
    pub fn empty_trash(&self) -> Result<()> {
        Ok(self.core().empty_trash()?)
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

    /// The links written in the bud at `path`, in order.
    pub fn links(&self, path: String) -> Result<Vec<LinkRecord>> {
        Ok(self
            .core()
            .links(&path)?
            .into_iter()
            .map(Into::into)
            .collect())
    }

    /// The links that name the bud at `path`.
    pub fn backlinks(&self, path: String) -> Result<Vec<LinkRecord>> {
        Ok(self
            .core()
            .backlinks(&path)?
            .into_iter()
            .map(Into::into)
            .collect())
    }

    /// Every link that names no bud, or more than one.
    pub fn unresolved_links(&self) -> Result<Vec<LinkRecord>> {
        Ok(self
            .core()
            .unresolved_links()?
            .into_iter()
            .map(Into::into)
            .collect())
    }

    /// Every picture in the index, by path; the Trash included, under `.trash/`.
    pub fn attachments(&self) -> Result<Vec<AttachmentRecord>> {
        Ok(self
            .core()
            .attachments()?
            .into_iter()
            .map(Into::into)
            .collect())
    }

    /// One picture by its path.
    pub fn attachment(&self, path: String) -> Result<Option<AttachmentRecord>> {
        Ok(self.core().attachment(&path)?.map(Into::into))
    }

    /// The embeds written in the bud at `path`, in order.
    pub fn embeds(&self, path: String) -> Result<Vec<EmbedRecord>> {
        Ok(self
            .core()
            .embeds(&path)?
            .into_iter()
            .map(Into::into)
            .collect())
    }

    /// The embeds that name the attachment at `path`.
    pub fn embedding(&self, path: String) -> Result<Vec<EmbedRecord>> {
        Ok(self
            .core()
            .embedding(&path)?
            .into_iter()
            .map(Into::into)
            .collect())
    }

    /// The first embed of the bud at `path` that names an attachment: the picture its card shows.
    pub fn first_embed(&self, path: String) -> Result<Option<EmbedRecord>> {
        Ok(self.core().first_embed(&path)?.map(Into::into))
    }

    /// Every tag with the number of buds that carry it, most used first.
    pub fn tags(&self) -> Result<Vec<TagCountRecord>> {
        Ok(self
            .core()
            .tags()?
            .into_iter()
            .map(|t| TagCountRecord {
                tag: t.tag,
                buds: t.buds as u64,
            })
            .collect())
    }

    /// The tags of the bud at `path`, in the order the file gives them.
    pub fn tags_of(&self, path: String) -> Result<Vec<String>> {
        Ok(self.core().tags_of(&path)?)
    }

    /// The buds that carry `tag`, in any case.
    pub fn tagged(&self, tag: String) -> Result<Vec<BudRecord>> {
        Ok(self
            .core()
            .tagged(&tag)?
            .into_iter()
            .map(Into::into)
            .collect())
    }

    /// Add `tag` to the bud's frontmatter; a bud that carries it already is left as it is.
    pub fn add_tag(&self, path: String, tag: String) -> Result<()> {
        Ok(self.core().add_tag(&path, &tag)?)
    }

    /// Take `tag` out of the bud's frontmatter; a `#tag` in its body stays. Returns the file it
    /// rewrote, for undo.
    pub fn remove_tag(&self, path: String, tag: String) -> Result<Option<TagEditRecord>> {
        Ok(self.core().remove_tag(&path, &tag)?.map(|e| TagEditRecord {
            path: e.path,
            before: e.before,
            after: e.after,
        }))
    }

    /// Rename or merge a tag across the vault. Returns each file it rewrote, for undo.
    pub fn rename_tag(&self, from: String, to: String) -> Result<Vec<TagEditRecord>> {
        Ok(self
            .core()
            .rename_tag(&from, &to)?
            .into_iter()
            .map(|e| TagEditRecord {
                path: e.path,
                before: e.before,
                after: e.after,
            })
            .collect())
    }

    /// Put back a file's text from before a tag rename, if the file still holds what the rename
    /// wrote. Returns whether it wrote.
    pub fn restore_text(&self, path: String, expected: String, text: String) -> Result<bool> {
        Ok(self.core().restore_text(&path, &expected, &text)?)
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
            bud_core::Place::Warehouse => BudPlace::Warehouse,
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
            from: bud.from,
            from_state: bud.from_state,
            body: bud.body,
            place: bud.place.into(),
            tags: bud.tags,
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

impl From<bud_core::Link> for LinkRecord {
    fn from(link: bud_core::Link) -> Self {
        LinkRecord {
            from: link.from,
            target: link.target,
            label: link.label,
            to: link.to,
        }
    }
}

impl From<bud_core::Attachment> for AttachmentRecord {
    fn from(attachment: bud_core::Attachment) -> Self {
        AttachmentRecord {
            path: attachment.path,
            name: attachment.name,
            size: attachment.size,
            mtime: attachment.mtime,
        }
    }
}

impl From<bud_core::Embed> for EmbedRecord {
    fn from(embed: bud_core::Embed) -> Self {
        EmbedRecord {
            from: embed.from,
            target: embed.target,
            label: embed.label,
            to: embed.to,
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

fn entries(pairs: Vec<(String, String)>) -> Vec<SharedEntry> {
    pairs
        .into_iter()
        .map(|(key, value)| SharedEntry { key, value })
        .collect()
}
