//! The peer transport: two vaults exchange documents directly, with no server that stores
//! anything.
//!
//! A [`Node`] runs an `iroh` endpoint for one open vault. Its node key lives in the index folder
//! beside the index, and so do the vault key, the peers and every ticket a person accepted; the
//! vault folder holds none of it. Peers on the same network find each other over mDNS; the relay
//! is the public default, one of the person's own, or off.
//!
//! Two vaults pair with a [`Ticket`]: the node id of the one that made it, its relay setting and
//! the vault key, as a short string and as the content of a QR code. The one that accepts a
//! ticket remembers the peer and takes the vault key of the ticket. The one that made it learns
//! the peer the first time that peer proves it holds the key, which is by sealing a message with
//! it.
//!
//! A ticket is one-shot on the side that made it: the maker records the ticket it issued and
//! accepts it from one node, once, within ten minutes of making it. A node the vault removed is refused even when it proves the key,
//! and a key rotation gives the remaining peers a new vault key over sessions sealed with the old
//! one, which voids the old key and every ticket made under it.
//!
//! Every message is sealed with the vault key (XChaCha20-Poly1305, a fresh nonce each) before it
//! goes on the wire, so a relay or a stranger on the network sees ciphertext only. A session is
//! one stream: the dialer sends its heads, the other answers with the changes the dialer lacks and
//! its own heads, the dialer sends the changes the other lacks, and the other confirms. Both sides
//! apply what they got through the sync module, which writes the files.
//!
//! What travels is the body and every frontmatter key: `state`, `when`, `due`, `pinned`, `created`
//! and `source` as properties, any other key, such as `tags`, as the lines the sender wrote, with
//! the order of the keys. A file made on the other side holds the same block.

use crate::lock;
use crate::sync::{Heads, Updates};
use crate::words::WORDS;
use crate::{Error, Result, SyncReport, Vault};
use chacha20poly1305::aead::{Aead, KeyInit, Payload};
use chacha20poly1305::{XChaCha20Poly1305, XNonce};
use data_encoding::{BASE32_NOPAD, HEXLOWER};
use iroh::endpoint::{presets, Incoming};
use iroh::{Endpoint, EndpointAddr, PublicKey, RelayMode, RelayUrl, SecretKey};
use iroh_mdns_address_lookup::MdnsAddressLookup;
use rusqlite::{params, OptionalExtension};
use serde::{Deserialize, Serialize};
use std::collections::HashSet;
use std::net::{IpAddr, Ipv4Addr, Ipv6Addr, SocketAddr};
use std::path::Path;
use std::str::FromStr;
use std::sync::atomic::{AtomicU64, AtomicUsize, Ordering};
use std::sync::{Arc, Mutex, MutexGuard};
use std::time::{Duration, SystemTime, UNIX_EPOCH};
use tokio::runtime::Runtime;

/// The protocol name two nodes agree on when they connect.
const ALPN: &[u8] = b"bud/sync/1";
/// The service name under which nodes announce themselves on the local network.
const MDNS_SERVICE: &str = "bud";
/// A ticket string starts with this, then the base32 of its fields.
const TICKET_PREFIX: &str = "bud1";
/// A join request as text starts with this.
const REQUEST_PREFIX: &str = "budr1";
/// What the six words of a request are derived under.
const WORDS_CONTEXT: &[u8] = b"bud/join/1";
/// Bound to the data a message is sealed with, so a sealed message of another use never opens.
const SEAL_CONTEXT: &[u8] = b"bud/sync/1";
const NODE_KEY_FILE: &str = "node.key";
/// The largest message accepted once the peer has proved it holds the key, sealed.
const MAX_FRAME: usize = 256 * 1024 * 1024;
/// The largest first message accepted from a caller that has proved nothing yet.
const MAX_HELLO: usize = 16 * 1024 * 1024;
const CHUNK: usize = 64 * 1024;
/// How many sessions a node answers at once.
const MAX_SESSIONS: usize = 16;
const SESSION_TIMEOUT: Duration = Duration::from_secs(60);
/// How long the person at a device that showed a join request has to keep or refuse the key a
/// phone brought; the phone waits a session for the answer.
const CONFIRM_TIMEOUT: Duration = Duration::from_secs(45);
const DEFAULT_INTERVAL: Duration = Duration::from_secs(5);

/// How long an issued ticket can be redeemed.
const TICKET_LIFETIME: Duration = Duration::from_secs(10 * 60);

fn now_millis() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_millis() as i64)
        .unwrap_or(0)
}

fn peer_error(err: impl std::fmt::Display) -> Error {
    Error::Invalid(format!("peer: {err}"))
}

/// How a node reaches the others when they are not on the same network.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub enum Relay {
    /// The public relays of the `iroh` project.
    Default,
    /// A relay of the person's own, by URL.
    Custom(String),
    /// No relay: direct connections only.
    Off,
}

impl Relay {
    fn to_text(&self) -> String {
        match self {
            Relay::Default => "default".to_string(),
            Relay::Off => "off".to_string(),
            Relay::Custom(url) => url.clone(),
        }
    }

    fn from_text(text: &str) -> Relay {
        match text {
            "default" => Relay::Default,
            "off" => Relay::Off,
            url => Relay::Custom(url.to_string()),
        }
    }

    fn url(&self) -> Result<Option<RelayUrl>> {
        match self {
            Relay::Custom(url) => RelayUrl::from_str(url)
                .map(Some)
                .map_err(|err| Error::Invalid(format!("relay url: {err}"))),
            _ => Ok(None),
        }
    }
}

/// What one vault gives another to pair with: the node id, the relay setting and the vault key.
/// `addrs` are direct addresses to try first; a ticket for another network leaves them empty.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Ticket {
    pub node: [u8; 32],
    /// Names this ticket to the vault that made it, which accepts it once.
    pub id: [u8; 16],
    pub relay: Relay,
    pub key: [u8; 32],
    pub addrs: Vec<SocketAddr>,
}

/// What a device without the vault shows to be let in, as G19 turns pairing around for a device
/// with no camera: its node id, where it listens, and a secret the session that brings the key is
/// sealed with. Six words derived from it are shown on both sides, so the person confirms the
/// phone scanned this device's code before any key moves.
#[derive(Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct JoinRequest {
    pub node: [u8; 32],
    pub secret: [u8; 32],
    /// When it was made, in milliseconds since the epoch; a request is refused after its lifetime.
    pub issued: i64,
    pub relay: Relay,
    pub addrs: Vec<SocketAddr>,
}

impl std::fmt::Debug for JoinRequest {
    /// Everything but the secret, which is not for a log.
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("JoinRequest")
            .field("node", &self.id())
            .field("issued", &self.issued)
            .field("relay", &self.relay)
            .field("addrs", &self.addrs)
            .finish_non_exhaustive()
    }
}

impl JoinRequest {
    /// The request as a string of letters and digits.
    pub fn encode(&self) -> String {
        let bytes = postcard::to_stdvec(self).unwrap_or_default();
        format!(
            "{REQUEST_PREFIX}{}",
            BASE32_NOPAD.encode(&bytes).to_ascii_lowercase()
        )
    }

    /// The request of a string; letter case does not matter.
    pub fn parse(text: &str) -> Result<JoinRequest> {
        let bad = |why: &str| Error::Invalid(format!("not a join request: {why}"));
        let text = text.trim().to_ascii_lowercase();
        let body = text
            .strip_prefix(REQUEST_PREFIX)
            .ok_or_else(|| bad("wrong start"))?;
        let bytes = BASE32_NOPAD
            .decode(body.to_ascii_uppercase().as_bytes())
            .map_err(|_| bad("not base32"))?;
        let (request, rest) =
            postcard::take_from_bytes::<JoinRequest>(&bytes).map_err(|_| bad("damaged"))?;
        if !rest.is_empty() {
            return Err(bad("trailing bytes"));
        }
        Ok(request)
    }

    /// The content of the QR code for this request.
    pub fn qr(&self) -> Result<Qr> {
        qr_of(&self.encode())
    }

    /// The requesting node's id in hex.
    pub fn id(&self) -> String {
        HEXLOWER.encode(&self.node)
    }

    /// The six words both sides show: a fingerprint of the whole request, so they match only
    /// when the phone scanned this device's code as this device made it. No word repeats in a
    /// set, since a repeat reads like a mistake to the person comparing.
    pub fn words(&self) -> [String; 6] {
        let mut hasher = blake3::Hasher::new();
        hasher.update(WORDS_CONTEXT);
        hasher.update(&self.node);
        hasher.update(&self.secret);
        hasher.update(&self.issued.to_le_bytes());
        // Each part of variable length goes in after its length, so no two requests hash alike.
        let relay = self.relay.to_text();
        hasher.update(&(relay.len() as u32).to_le_bytes());
        hasher.update(relay.as_bytes());
        hasher.update(&(self.addrs.len() as u32).to_le_bytes());
        for addr in &self.addrs {
            let addr = addr.to_string();
            hasher.update(&(addr.len() as u32).to_le_bytes());
            hasher.update(addr.as_bytes());
        }
        let mut reader = hasher.finalize_xof();
        let mut chosen: Vec<usize> = Vec::with_capacity(6);
        while chosen.len() < 6 {
            let mut bytes = [0u8; 32];
            reader.fill(&mut bytes);
            for byte in bytes {
                let index = byte as usize;
                if chosen.len() < 6 && !chosen.contains(&index) {
                    chosen.push(index);
                }
            }
        }
        std::array::from_fn(|i| WORDS[chosen[i]].to_string())
    }

    /// Whether the request is past its lifetime at `now` milliseconds. One that claims to be made
    /// more than a lifetime ahead of now did not come from a clock, and is past too.
    pub fn is_expired(&self, lifetime: Duration, now: i64) -> bool {
        let lifetime = i64::try_from(lifetime.as_millis()).unwrap_or(i64::MAX);
        now.saturating_sub(self.issued) >= lifetime || self.issued.saturating_sub(now) > lifetime
    }
}

/// The modules of a QR code for `text`. Upper case lets the code use its denser alphanumeric
/// mode; parsing ignores case.
fn qr_of(text: &str) -> Result<Qr> {
    let code = qrcode::QrCode::new(text.to_ascii_uppercase().as_bytes())
        .map_err(|err| Error::Invalid(format!("qr code: {err}")))?;
    Ok(Qr {
        width: code.width(),
        dark: code
            .to_colors()
            .into_iter()
            .map(|c| c == qrcode::Color::Dark)
            .collect(),
    })
}

/// What a key rotation did: the peers that took the new key, and the ones it could not reach.
/// A peer that missed it holds the old key and is turned away until it pairs again.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RotateReport {
    pub reached: usize,
    pub missed: Vec<String>,
}

/// How one peer fared in a key rotation: it confirmed the hand over, or the hand over did not
/// come back and a probe said whether it holds the new key.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum RotationOutcome {
    Confirmed,
    Probed { holds_key: bool },
}

/// What a node tells its listeners as it goes, for the screens that show pairing and syncing.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum NodeEvent {
    /// A node redeemed a ticket this vault issued, in its first session.
    TicketRedeemed { by: String },
    /// A node this vault did not know is now a peer.
    PeerJoined { id: String },
    /// A node that holds a vault brought its key to the join request this node shows: the words
    /// of that request and what the node says it is. The key is kept only once
    /// [`Node::answer_join`] says so.
    JoinOffered {
        id: String,
        kind: Option<String>,
        name: Option<String>,
        words: Vec<String>,
    },
    /// One peer's part of a key rotation, as it happens.
    KeyRotation {
        id: String,
        outcome: RotationOutcome,
    },
    /// The rotation is over; the same report [`Node::rotate_key`] returns.
    RotationDone(RotateReport),
    /// A first fetch from a peer: how many documents arrived, and how many buds the peer holds
    /// when it said.
    FetchProgress {
        received: usize,
        total: Option<usize>,
    },
    /// Changes from peers were applied here: what they did, for a session this node answered or
    /// for every session of a sync it dialed. Only when buds changed; the files are written by
    /// the vault, so the watcher does not report them.
    SyncFinished(SyncReport),
}

/// Told each [`NodeEvent`] as it happens, from the node's own threads.
pub trait NodeListener: Send + Sync + 'static {
    fn event(&self, event: NodeEvent);
}

/// A QR code as a square of modules, row by row; `true` is dark.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Qr {
    pub width: usize,
    pub dark: Vec<bool>,
}

impl Ticket {
    /// The ticket as a string of letters and digits.
    pub fn encode(&self) -> String {
        // Plain data with no maps: serializing it cannot fail.
        let bytes = postcard::to_stdvec(self).unwrap_or_default();
        format!(
            "{TICKET_PREFIX}{}",
            BASE32_NOPAD.encode(&bytes).to_ascii_lowercase()
        )
    }

    /// The ticket of a string; letter case does not matter.
    pub fn parse(text: &str) -> Result<Ticket> {
        let bad = |why: &str| Error::Invalid(format!("not a pairing ticket: {why}"));
        let text = text.trim().to_ascii_lowercase();
        let body = text
            .strip_prefix(TICKET_PREFIX)
            .ok_or_else(|| bad("wrong start"))?;
        let bytes = BASE32_NOPAD
            .decode(body.to_ascii_uppercase().as_bytes())
            .map_err(|_| bad("not base32"))?;
        let (ticket, rest) =
            postcard::take_from_bytes::<Ticket>(&bytes).map_err(|_| bad("damaged"))?;
        if !rest.is_empty() {
            return Err(bad("trailing bytes"));
        }
        Ok(ticket)
    }

    /// The content of the QR code for this ticket.
    pub fn qr(&self) -> Result<Qr> {
        qr_of(&self.encode())
    }
}

/// A peer this vault remembers.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PeerInfo {
    /// The node id in hex.
    pub id: String,
    pub relay: Relay,
    pub addrs: Vec<SocketAddr>,
    /// When the peer last took part in a session, in seconds since the epoch; none before the
    /// first.
    pub last_seen: Option<i64>,
    /// The last key rotation could not move this peer: it holds the old key and is turned away
    /// until it pairs again.
    pub missed: bool,
    /// What the peer said it is in its last session: `mac`, `iphone`, `ipad` or `tv`; none from
    /// a build that does not say.
    pub kind: Option<String>,
    /// The name the peer's system gives it, as the peer sent it.
    pub name: Option<String>,
    /// The label this vault gave the peer, preferred over `name` when shown.
    pub label: Option<String>,
}

/// What a node says it is in the first message of a session: its kind and its system name.
/// Both are optional, so a build that says nothing still syncs.
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct Identity {
    pub kind: Option<String>,
    pub name: Option<String>,
}

impl Identity {
    pub fn new(kind: impl Into<String>, name: impl Into<String>) -> Identity {
        Identity {
            kind: Some(kind.into()),
            name: Some(name.into()),
        }
    }

    fn is_empty(&self) -> bool {
        self.kind.is_none() && self.name.is_none()
    }
}

/// What a node is doing: whether a sync is running, how many peers it reached on their last
/// session, and how many files have edits the next sync will take.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct NodeState {
    pub syncing: bool,
    pub connected: usize,
    pub pending: usize,
}

/// How a node starts.
#[derive(Debug, Clone)]
pub struct NodeOptions {
    pub relay: Relay,
    /// How often to look at the folder and sync with every peer; none leaves it to
    /// [`Node::sync_now`].
    pub interval: Option<Duration>,
    /// What this node tells its peers it is.
    pub identity: Identity,
}

impl NodeOptions {
    pub fn new(relay: Relay) -> NodeOptions {
        NodeOptions {
            relay,
            interval: Some(DEFAULT_INTERVAL),
            identity: Identity::default(),
        }
    }

    pub fn with_identity(mut self, identity: Identity) -> NodeOptions {
        self.identity = identity;
        self
    }
}

// What a vault keeps for the transport, in the index.
impl Vault {
    /// The vault key. Made on first use.
    fn peer_key(&self) -> Result<[u8; 32]> {
        let conn = lock(&self.conn);
        let read = || -> Result<Option<Vec<u8>>> {
            Ok(conn
                .query_row("SELECT key FROM peer_key WHERE id = 1", [], |r| r.get(0))
                .optional()?)
        };
        let key = match read()? {
            Some(key) => key,
            None => {
                let mut fresh = [0u8; 32];
                getrandom::fill(&mut fresh).map_err(peer_error)?;
                conn.execute(
                    "INSERT OR IGNORE INTO peer_key (id, key) VALUES (1, ?1)",
                    params![fresh.to_vec()],
                )?;
                read()?.unwrap_or_else(|| fresh.to_vec())
            }
        };
        key.try_into()
            .map_err(|_| Error::Invalid("peer: the vault key is damaged".to_string()))
    }

    /// Take the key of a ticket. A vault that has peers already keeps its own.
    fn adopt_key(&self, key: &[u8; 32]) -> Result<()> {
        if &self.peer_key()? == key {
            return Ok(());
        }
        if !self.peer_list()?.is_empty() {
            return Err(Error::Invalid(
                "peer: this vault is paired with another vault already".to_string(),
            ));
        }
        lock(&self.conn).execute(
            "INSERT INTO peer_key (id, key) VALUES (1, ?1)
             ON CONFLICT(id) DO UPDATE SET key = excluded.key",
            params![key.to_vec()],
        )?;
        Ok(())
    }

    /// Remember a peer. False when it was known.
    fn remember_peer(&self, id: &str, relay: &Relay, addrs: &[SocketAddr]) -> Result<bool> {
        let added = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .map(|d| d.as_secs() as i64)
            .unwrap_or(0);
        let addrs: Vec<String> = addrs.iter().map(SocketAddr::to_string).collect();
        let changed = lock(&self.conn).execute(
            "INSERT OR IGNORE INTO peers (node, relay, addrs, added) VALUES (?1, ?2, ?3, ?4)",
            params![id, relay.to_text(), addrs.join("\n"), added],
        )?;
        Ok(changed == 1)
    }

    /// Keep what a peer said it is. A field it left out keeps the last value it sent.
    fn note_identity(&self, id: &str, identity: &Identity) -> Result<()> {
        if identity.is_empty() {
            return Ok(());
        }
        lock(&self.conn).execute(
            "INSERT INTO peer_identity (node, kind, name) VALUES (?1, ?2, ?3)
             ON CONFLICT(node) DO UPDATE SET
                 kind = COALESCE(excluded.kind, kind),
                 name = COALESCE(excluded.name, name)",
            params![id, identity.kind, identity.name],
        )?;
        Ok(())
    }

    /// Give a peer a label of this vault's own, or take it away with none or an empty one.
    fn label_peer(&self, id: &str, label: Option<&str>) -> Result<()> {
        let conn = lock(&self.conn);
        let known: bool = conn.query_row(
            "SELECT COUNT(*) > 0 FROM peers WHERE node = ?1",
            params![id],
            |r| r.get(0),
        )?;
        if !known {
            return Err(Error::Invalid(format!("peer: no peer {id}")));
        }
        match label.map(str::trim).filter(|l| !l.is_empty()) {
            Some(label) => conn.execute(
                "INSERT INTO peer_label (node, label) VALUES (?1, ?2)
                 ON CONFLICT(node) DO UPDATE SET label = excluded.label",
                params![id, label],
            )?,
            None => conn.execute("DELETE FROM peer_label WHERE node = ?1", params![id])?,
        };
        Ok(())
    }

    fn peer_list(&self) -> Result<Vec<PeerInfo>> {
        let conn = lock(&self.conn);
        let mut stmt = conn.prepare(
            "SELECT peers.node, relay, addrs, seen, peer_missed.node IS NOT NULL,
                    peer_identity.kind, peer_identity.name, peer_label.label
             FROM peers
             LEFT JOIN peer_seen ON peer_seen.node = peers.node
             LEFT JOIN peer_missed ON peer_missed.node = peers.node
             LEFT JOIN peer_identity ON peer_identity.node = peers.node
             LEFT JOIN peer_label ON peer_label.node = peers.node
             ORDER BY added, peers.node",
        )?;
        let rows = stmt.query_map([], |r| {
            Ok((
                r.get::<_, String>(0)?,
                r.get::<_, String>(1)?,
                r.get::<_, String>(2)?,
                r.get::<_, Option<i64>>(3)?,
                r.get::<_, bool>(4)?,
                r.get::<_, Option<String>>(5)?,
                r.get::<_, Option<String>>(6)?,
                r.get::<_, Option<String>>(7)?,
            ))
        })?;
        let mut peers = Vec::new();
        for row in rows {
            let (id, relay, addrs, last_seen, missed, kind, name, label) = row?;
            peers.push(PeerInfo {
                id,
                relay: Relay::from_text(&relay),
                addrs: addrs.lines().filter_map(|a| a.parse().ok()).collect(),
                last_seen,
                missed,
                kind,
                name,
                label,
            });
        }
        Ok(peers)
    }

    /// Note that a peer took part in a session just now.
    fn touch_peer(&self, id: &str) -> Result<()> {
        let seen = now_millis() / 1000;
        let conn = lock(&self.conn);
        conn.execute(
            "INSERT INTO peer_seen (node, seen) VALUES (?1, ?2)
             ON CONFLICT(node) DO UPDATE SET seen = excluded.seen",
            params![id, seen],
        )?;
        // A session sealed with the vault key worked, so the peer holds it.
        conn.execute("DELETE FROM peer_missed WHERE node = ?1", params![id])?;
        Ok(())
    }

    /// Forget a peer and refuse its node id from now on, even when it proves the vault key.
    fn forget(&self, id: &str) -> Result<()> {
        let conn = lock(&self.conn);
        conn.execute("DELETE FROM peer_seen WHERE node = ?1", params![id])?;
        conn.execute("DELETE FROM peer_ticket WHERE node = ?1", params![id])?;
        conn.execute("DELETE FROM peer_missed WHERE node = ?1", params![id])?;
        conn.execute("DELETE FROM peer_identity WHERE node = ?1", params![id])?;
        conn.execute("DELETE FROM peer_label WHERE node = ?1", params![id])?;
        match conn.execute("DELETE FROM peers WHERE node = ?1", params![id])? {
            0 => Err(Error::Invalid(format!("peer: no peer {id}"))),
            _ => {
                conn.execute(
                    "INSERT OR IGNORE INTO peer_denied (node) VALUES (?1)",
                    params![id],
                )?;
                Ok(())
            }
        }
    }

    /// Lift the refusal of a node this vault removed.
    fn allow(&self, id: &str) -> Result<()> {
        lock(&self.conn).execute("DELETE FROM peer_denied WHERE node = ?1", params![id])?;
        Ok(())
    }

    fn is_denied(&self, id: &str) -> Result<bool> {
        Ok(lock(&self.conn)
            .query_row(
                "SELECT 1 FROM peer_denied WHERE node = ?1",
                params![id],
                |_| Ok(()),
            )
            .optional()?
            .is_some())
    }

    fn is_peer(&self, id: &str) -> Result<bool> {
        Ok(self.peer_list()?.iter().any(|peer| peer.id == id))
    }

    /// Make a ticket id and record it as issued. Tickets older than `lifetime` are dropped first,
    /// so the table does not grow with every QR code that is refreshed.
    fn issue_ticket(&self, lifetime: Duration) -> Result<[u8; 16]> {
        let mut id = [0u8; 16];
        getrandom::fill(&mut id).map_err(peer_error)?;
        let now = now_millis();
        let conn = lock(&self.conn);
        conn.execute(
            "DELETE FROM tickets_issued WHERE issued <= ?1",
            params![now - lifetime.as_millis() as i64],
        )?;
        conn.execute(
            "INSERT INTO tickets_issued (id, issued) VALUES (?1, ?2)",
            params![id.to_vec(), now],
        )?;
        Ok(id)
    }

    /// Use up an issued ticket. False when it was never issued, expired or was redeemed already.
    fn redeem_ticket(&self, id: &[u8; 16], lifetime: Duration) -> Result<bool> {
        let changed = lock(&self.conn).execute(
            "DELETE FROM tickets_issued WHERE id = ?1 AND issued > ?2",
            params![id.to_vec(), now_millis() - lifetime.as_millis() as i64],
        )?;
        Ok(changed == 1)
    }

    /// Note that a rotation could not move a peer: it holds the old key.
    fn mark_missed(&self, id: &str) -> Result<()> {
        lock(&self.conn).execute(
            "INSERT OR IGNORE INTO peer_missed (node) VALUES (?1)",
            params![id],
        )?;
        Ok(())
    }

    fn pending_ticket(&self, node: &str) -> Result<Option<[u8; 16]>> {
        let found: Option<Vec<u8>> = lock(&self.conn)
            .query_row(
                "SELECT ticket FROM peer_ticket WHERE node = ?1",
                params![node],
                |r| r.get(0),
            )
            .optional()?;
        Ok(found.and_then(|bytes| bytes.try_into().ok()))
    }

    fn keep_pending_ticket(&self, node: &str, ticket: &[u8; 16]) -> Result<()> {
        lock(&self.conn).execute(
            "INSERT INTO peer_ticket (node, ticket) VALUES (?1, ?2)
             ON CONFLICT(node) DO UPDATE SET ticket = excluded.ticket",
            params![node, ticket.to_vec()],
        )?;
        Ok(())
    }

    fn clear_pending_ticket(&self, node: &str) -> Result<()> {
        lock(&self.conn).execute("DELETE FROM peer_ticket WHERE node = ?1", params![node])?;
        Ok(())
    }

    /// Replace the vault key. Tickets issued under the old one are void.
    fn replace_key(&self, key: &[u8; 32]) -> Result<()> {
        let conn = lock(&self.conn);
        conn.execute(
            "INSERT INTO peer_key (id, key) VALUES (1, ?1)
             ON CONFLICT(id) DO UPDATE SET key = excluded.key",
            params![key.to_vec()],
        )?;
        conn.execute("DELETE FROM tickets_issued", [])?;
        // Whoever took the new key is not on the old one any more; a rotation marks the ones that
        // did not, after this.
        conn.execute("DELETE FROM peer_missed", [])?;
        Ok(())
    }
}

/// Seal `plain` with the vault key: a fresh nonce, then the ciphertext and its tag.
/// `from` is who speaks, so a message sent one way never opens as one sent the other way.
fn seal(key: &[u8; 32], from: Side, plain: &[u8]) -> Result<Vec<u8>> {
    let mut nonce = [0u8; 24];
    getrandom::fill(&mut nonce).map_err(peer_error)?;
    let cipher = XChaCha20Poly1305::new(key.into());
    let sealed = cipher
        .encrypt(
            XNonce::from_slice(&nonce),
            Payload {
                msg: plain,
                aad: &context(from),
            },
        )
        .map_err(|_| peer_error("could not seal a message"))?;
    let mut out = nonce.to_vec();
    out.extend(sealed);
    Ok(out)
}

/// Open what [`seal`] made. A wrong key or a changed byte is an error.
fn open(key: &[u8; 32], from: Side, sealed: &[u8]) -> Result<Vec<u8>> {
    if sealed.len() < 24 {
        return Err(peer_error("a message is too short"));
    }
    let (nonce, body) = sealed.split_at(24);
    XChaCha20Poly1305::new(key.into())
        .decrypt(
            XNonce::from_slice(nonce),
            Payload {
                msg: body,
                aad: &context(from),
            },
        )
        .map_err(|_| peer_error("a message did not open with the vault key"))
}

#[derive(Serialize, Deserialize)]
enum Message {
    /// The dialer's heads, and the ticket it redeems when this is its first session.
    Hello {
        heads: Heads,
        ticket: Option<[u8; 16]>,
    },
    /// The dialer hands over a new vault key; the answerer confirms with `Done`.
    Rotate([u8; 32]),
    /// The dialer asks whether the answerer holds the key it seals this with; the answerer
    /// confirms with `Done`.
    Probe,
    Reply {
        updates: Updates,
        heads: Heads,
    },
    Final(Updates),
    Done,
    /// The dialer, which holds the vault, brings its key to a node that showed a join request,
    /// sealed with the request's secret; the answerer confirms with `Done` once the person at it
    /// kept the key, or answers `Refused`.
    Join {
        key: [u8; 32],
        relay: Relay,
    },
    /// The person at the answerer refused the key a `Join` brought.
    Refused,
}

/// The end of a session that speaks: the one that dialed, or the one that answered.
#[derive(Clone, Copy, PartialEq, Eq)]
enum Side {
    Dialer,
    Answerer,
}

fn context(from: Side) -> Vec<u8> {
    let mut aad = SEAL_CONTEXT.to_vec();
    aad.push(from as u8);
    aad
}

/// What a node says about itself after a message: who it is, and with a Reply how many buds it
/// holds, so a first fetch can show its size before it ends.
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
struct Aside {
    kind: Option<String>,
    name: Option<String>,
    buds: Option<u64>,
}

impl Aside {
    fn new(identity: &Identity, buds: Option<usize>) -> Aside {
        Aside {
            kind: identity.kind.clone(),
            name: identity.name.clone(),
            buds: buds.map(|n| n as u64),
        }
    }

    fn identity(&self) -> Identity {
        Identity {
            kind: self.kind.clone(),
            name: self.name.clone(),
        }
    }

    fn is_empty(&self) -> bool {
        self.kind.is_none() && self.name.is_none() && self.buds.is_none()
    }
}

/// A message as the bytes of a frame, with the sender's aside after it when there is one. An
/// older build reads the message and ignores the rest; a newer one reads both.
fn encode(message: &Message, aside: &Aside) -> Result<Vec<u8>> {
    let mut plain = postcard::to_stdvec(message).map_err(peer_error)?;
    if !aside.is_empty() {
        plain.extend(postcard::to_stdvec(aside).map_err(peer_error)?);
    }
    Ok(plain)
}

/// The message of a frame, and the aside after it when the sender put one there. A build that
/// sent the identity alone still reads; a trailer that reads as neither is treated as none, since
/// it is only words about the peer.
fn decode(plain: &[u8]) -> Result<(Message, Aside)> {
    let (message, rest) = postcard::take_from_bytes::<Message>(plain).map_err(peer_error)?;
    let aside = if rest.is_empty() {
        Aside::default()
    } else {
        postcard::from_bytes::<Aside>(rest)
            .or_else(|_| postcard::from_bytes::<Identity>(rest).map(|id| Aside::new(&id, None)))
            .unwrap_or_default()
    };
    Ok((message, aside))
}

async fn send_message(
    send: &mut iroh::endpoint::SendStream,
    key: &[u8; 32],
    from: Side,
    message: &Message,
) -> Result<()> {
    send_with_aside(send, key, from, message, &Aside::default()).await
}

async fn send_with_aside(
    send: &mut iroh::endpoint::SendStream,
    key: &[u8; 32],
    from: Side,
    message: &Message,
    aside: &Aside,
) -> Result<()> {
    let plain = encode(message, aside)?;
    let sealed = seal(key, from, &plain)?;
    let len = u32::try_from(sealed.len()).map_err(peer_error)?;
    send.write_all(&len.to_be_bytes())
        .await
        .map_err(peer_error)?;
    send.write_all(&sealed).await.map_err(peer_error)
}

/// Read one message sent by `from`, at most `max` bytes sealed. The buffer grows with what
/// arrives, so a length a peer claims costs nothing until the bytes are there.
async fn read_message(
    recv: &mut iroh::endpoint::RecvStream,
    key: &[u8; 32],
    from: Side,
    max: usize,
) -> Result<Message> {
    Ok(read_with_aside(recv, key, from, max).await?.0)
}

/// Read one message and the aside its sender put after it, if any.
async fn read_with_aside(
    recv: &mut iroh::endpoint::RecvStream,
    key: &[u8; 32],
    from: Side,
    max: usize,
) -> Result<(Message, Aside)> {
    let sealed = read_frame(recv, max).await?;
    open_frame(key, from, &sealed)
}

/// The message of a sealed frame, and its aside.
fn open_frame(key: &[u8; 32], from: Side, sealed: &[u8]) -> Result<(Message, Aside)> {
    decode(&open(key, from, sealed)?)
}

/// Read one sealed frame of at most `max` bytes, as sent.
async fn read_frame(recv: &mut iroh::endpoint::RecvStream, max: usize) -> Result<Vec<u8>> {
    let mut len = [0u8; 4];
    recv.read_exact(&mut len).await.map_err(peer_error)?;
    let len = u32::from_be_bytes(len) as usize;
    if len > max {
        return Err(peer_error("a message is too large"));
    }
    let mut sealed = Vec::new();
    let mut chunk = vec![0u8; CHUNK.min(len)];
    while sealed.len() < len {
        let want = CHUNK.min(len - sealed.len());
        recv.read_exact(&mut chunk[..want])
            .await
            .map_err(peer_error)?;
        sealed.extend_from_slice(&chunk[..want]);
    }
    Ok(sealed)
}

/// The node key, read from `path`, or made and written there for the first time.
fn node_key(path: &Path) -> Result<SecretKey> {
    match std::fs::read(path) {
        Ok(bytes) => {
            let bytes: [u8; 32] = bytes
                .try_into()
                .map_err(|_| Error::Invalid(format!("peer: {NODE_KEY_FILE} is damaged")))?;
            Ok(SecretKey::from_bytes(&bytes))
        }
        Err(err) if err.kind() == std::io::ErrorKind::NotFound => {
            let mut bytes = [0u8; 32];
            getrandom::fill(&mut bytes).map_err(peer_error)?;
            write_private(path, &bytes)?;
            Ok(SecretKey::from_bytes(&bytes))
        }
        Err(err) => Err(err.into()),
    }
}

fn write_private(path: &Path, bytes: &[u8]) -> Result<()> {
    use std::io::Write;
    let mut options = std::fs::OpenOptions::new();
    options.write(true).create_new(true);
    #[cfg(unix)]
    std::os::unix::fs::OpenOptionsExt::mode(&mut options, 0o600);
    options.open(path)?.write_all(bytes)?;
    Ok(())
}

async fn bind(secret: SecretKey, relay: &Relay) -> Result<Endpoint> {
    let builder = match relay {
        // The default preset also finds a peer by its id alone through the public lookup.
        Relay::Default => Endpoint::builder(presets::N0),
        Relay::Custom(_) => Endpoint::builder(presets::Minimal),
        Relay::Off => Endpoint::builder(presets::Minimal),
    };
    let builder = match relay {
        Relay::Custom(_) => match relay.url()? {
            Some(url) => builder.relay_mode(RelayMode::custom([url])),
            None => builder,
        },
        Relay::Off => builder.relay_mode(RelayMode::Disabled),
        Relay::Default => builder,
    };
    builder
        .secret_key(secret)
        .alpns(vec![ALPN.to_vec()])
        .address_lookup(MdnsAddressLookup::builder().service_name(MDNS_SERVICE))
        .bind()
        .await
        .map_err(peer_error)
}

fn id_text(id: &PublicKey) -> String {
    HEXLOWER.encode(id.as_bytes())
}

struct Shared {
    endpoint: Endpoint,
    vault: Arc<Mutex<Vault>>,
    relay: Relay,
    /// Peers whose last session worked.
    connected: Mutex<HashSet<String>>,
    /// Sessions running now, dialed or answered.
    active: AtomicUsize,
    /// How long an issued ticket can be redeemed, in milliseconds.
    ticket_lifetime_ms: AtomicU64,
    /// How many confirmations of a new key to withhold; only tests make it more than zero.
    dropped_acks: AtomicUsize,
    /// What this node tells its peers it is.
    identity: Identity,
    /// Who hears what happens.
    listeners: Mutex<Vec<Box<dyn NodeListener>>>,
    /// The join request this node shows, until it is used or replaced.
    request: Mutex<Option<JoinRequest>>,
    /// Where the answer to the key on offer goes, while a session waits for it, under the secret
    /// of the request the key came to, so one session never clears another's offer.
    offer: Mutex<Option<([u8; 32], tokio::sync::oneshot::Sender<bool>)>>,
}

/// Counts a running session for as long as it lives.
struct Busy<'a>(&'a AtomicUsize);

impl<'a> Busy<'a> {
    fn new(count: &'a AtomicUsize) -> Busy<'a> {
        count.fetch_add(1, Ordering::SeqCst);
        Busy(count)
    }
}

impl Drop for Busy<'_> {
    fn drop(&mut self) {
        self.0.fetch_sub(1, Ordering::SeqCst);
    }
}

impl Shared {
    fn vault(&self) -> MutexGuard<'_, Vault> {
        lock(&self.vault)
    }

    fn ticket_lifetime(&self) -> Duration {
        Duration::from_millis(self.ticket_lifetime_ms.load(Ordering::SeqCst))
    }

    fn reached(&self, id: &str) {
        let _ = self.vault().touch_peer(id);
        lock(&self.connected).insert(id.to_string());
    }

    fn lost(&self, id: &str) {
        lock(&self.connected).remove(id);
    }

    /// Open a first frame with the secret of the request this node shows, while the request
    /// lasts. A frame that opens takes the request with it, under the lock, so it is good once
    /// whatever two callers do at the same time.
    fn take_join(&self, sealed: &[u8]) -> Option<(JoinRequest, [u8; 32], Relay, Aside)> {
        let lifetime = self.ticket_lifetime();
        let mut slot = lock(&self.request);
        let opened = slot
            .as_ref()
            .filter(|request| !request.is_expired(lifetime, now_millis()))
            .and_then(
                |request| match open_frame(&request.secret, Side::Dialer, sealed) {
                    Ok((Message::Join { key, relay }, aside)) => Some((key, relay, aside)),
                    _ => None,
                },
            );
        let (key, relay, aside) = opened?;
        slot.take().map(|request| (request, key, relay, aside))
    }

    /// The addresses this node listens on, loopback included, for a peer that cannot look it up.
    fn listen_addrs(&self) -> Vec<SocketAddr> {
        let endpoint = &self.endpoint;
        let mut addrs: Vec<SocketAddr> = endpoint.addr().ip_addrs().copied().collect();
        for bound in endpoint.bound_sockets() {
            if bound.ip().is_unspecified() {
                let loopback = match bound.ip() {
                    IpAddr::V4(_) => IpAddr::V4(Ipv4Addr::LOCALHOST),
                    IpAddr::V6(_) => IpAddr::V6(Ipv6Addr::LOCALHOST),
                };
                addrs.push(SocketAddr::new(loopback, bound.port()));
            } else {
                addrs.push(bound);
            }
        }
        addrs.sort();
        addrs.dedup();
        addrs
    }

    /// Bring the vault key to the node that showed `request`, over a session sealed with the
    /// request's secret.
    async fn offer(&self, request: &JoinRequest) -> Result<()> {
        let key = self.vault().peer_key()?;
        let peer = PeerInfo {
            id: request.id(),
            relay: request.relay.clone(),
            addrs: request.addrs.clone(),
            last_seen: None,
            missed: false,
            kind: None,
            name: None,
            label: None,
        };
        let connection = self
            .endpoint
            .connect(self.address_of(&peer)?, ALPN)
            .await
            .map_err(peer_error)?;
        let (mut send, mut recv) = connection.open_bi().await.map_err(peer_error)?;
        send_with_aside(
            &mut send,
            &request.secret,
            Side::Dialer,
            &Message::Join {
                key,
                relay: self.relay.clone(),
            },
            &Aside::new(&self.identity, None),
        )
        .await?;
        match read_message(&mut recv, &request.secret, Side::Answerer, MAX_FRAME).await {
            Ok(Message::Done) => {}
            Ok(Message::Refused) => return Err(peer_error("the device refused the key")),
            _ => return Err(peer_error("the device did not confirm the key")),
        }
        send.finish().map_err(peer_error)?;
        connection.close(0u32.into(), b"done");
        Ok(())
    }

    fn emit(&self, event: NodeEvent) {
        for listener in lock(&self.listeners).iter() {
            listener.event(event.clone());
        }
    }

    /// Look at the folder, then sync with every peer. An error only when no peer could be synced.
    async fn sync_all(&self) -> Result<SyncReport> {
        let _busy = Busy::new(&self.active);
        let mut report = {
            let mut vault = self.vault();
            vault.rescan()?;
            vault.sync()?
        };
        let peers = self.vault().peer_list()?;
        let mut failure = None;
        let mut reached = false;
        let mut received = SyncReport::default();
        for peer in &peers {
            match tokio::time::timeout(SESSION_TIMEOUT, self.exchange(peer)).await {
                Ok(Ok(done)) => {
                    report.add(done);
                    received.add(done);
                    reached = true;
                    self.reached(&peer.id);
                }
                Ok(Err(err)) => {
                    self.lost(&peer.id);
                    failure = failure.or(Some(err));
                }
                Err(_) => {
                    self.lost(&peer.id);
                    failure = failure.or(Some(peer_error("a peer did not answer")));
                }
            }
        }
        if received.changed() {
            self.emit(NodeEvent::SyncFinished(received));
        }
        match failure {
            Some(err) if !reached => Err(err),
            _ => Ok(report),
        }
    }

    fn address_of(&self, peer: &PeerInfo) -> Result<EndpointAddr> {
        let bytes: [u8; 32] = HEXLOWER
            .decode(peer.id.as_bytes())
            .map_err(peer_error)?
            .try_into()
            .map_err(|_| peer_error("a node id is damaged"))?;
        let mut addr = EndpointAddr::new(PublicKey::from_bytes(&bytes).map_err(peer_error)?);
        if let Some(url) = peer.relay.url()? {
            addr = addr.with_relay_url(url);
        }
        for ip in &peer.addrs {
            addr = addr.with_ip_addr(*ip);
        }
        Ok(addr)
    }

    /// Dial a peer and run one session.
    async fn exchange(&self, peer: &PeerInfo) -> Result<SyncReport> {
        let key = self.vault().peer_key()?;
        let connection = self
            .endpoint
            .connect(self.address_of(peer)?, ALPN)
            .await
            .map_err(peer_error)?;
        let (mut send, mut recv) = connection.open_bi().await.map_err(peer_error)?;
        let (heads, ticket) = {
            let vault = self.vault();
            (vault.heads()?, vault.pending_ticket(&peer.id)?)
        };
        // A first fetch: the session that redeems a ticket, or the first with a peer that brought
        // the key to a join request, which has not been seen in a session yet.
        let first = ticket.is_some() || peer.last_seen.is_none();
        send_with_aside(
            &mut send,
            &key,
            Side::Dialer,
            &Message::Hello { heads, ticket },
            &Aside::new(&self.identity, None),
        )
        .await?;
        let (Message::Reply { updates, heads }, theirs) =
            read_with_aside(&mut recv, &key, Side::Answerer, MAX_FRAME).await?
        else {
            return Err(peer_error("a peer answered out of turn"));
        };
        self.vault().note_identity(&peer.id, &theirs.identity())?;
        let total = theirs.buds.map(|n| n as usize);
        if first {
            // The first fetch: its size before anything is applied, then what arrived.
            self.emit(NodeEvent::FetchProgress { received: 0, total });
        }
        let report = self.vault().apply_updates(&updates)?;
        if first {
            self.emit(NodeEvent::FetchProgress {
                received: updates.doc_count(),
                total,
            });
        }
        let mine = self.vault().updates_for(&heads)?;
        send_message(&mut send, &key, Side::Dialer, &Message::Final(mine)).await?;
        let Message::Done = read_message(&mut recv, &key, Side::Answerer, MAX_FRAME).await? else {
            return Err(peer_error("a peer did not confirm"));
        };
        send.finish().map_err(peer_error)?;
        connection.close(0u32.into(), b"done");
        // The peer took the ticket; it is spent.
        self.vault().clear_pending_ticket(&peer.id)?;
        Ok(report)
    }

    /// Hand a peer the new vault key over a session sealed with the old one.
    async fn hand_over(&self, peer: &PeerInfo, old: &[u8; 32], new: &[u8; 32]) -> Result<()> {
        let connection = self
            .endpoint
            .connect(self.address_of(peer)?, ALPN)
            .await
            .map_err(peer_error)?;
        let (mut send, mut recv) = connection.open_bi().await.map_err(peer_error)?;
        send_message(&mut send, old, Side::Dialer, &Message::Rotate(*new)).await?;
        let Message::Done = read_message(&mut recv, old, Side::Answerer, MAX_FRAME).await? else {
            return Err(peer_error("a peer did not confirm the new key"));
        };
        send.finish().map_err(peer_error)?;
        connection.close(0u32.into(), b"done");
        Ok(())
    }

    /// Ask a peer whether it holds `key`, over a session sealed with it. Used after a hand over
    /// whose confirmation did not arrive, to tell a lost acknowledgement from a missed key.
    async fn holds_key(&self, peer: &PeerInfo, key: &[u8; 32]) -> Result<()> {
        let connection = self
            .endpoint
            .connect(self.address_of(peer)?, ALPN)
            .await
            .map_err(peer_error)?;
        let (mut send, mut recv) = connection.open_bi().await.map_err(peer_error)?;
        send_message(&mut send, key, Side::Dialer, &Message::Probe).await?;
        let Message::Done = read_message(&mut recv, key, Side::Answerer, MAX_FRAME).await? else {
            return Err(peer_error("a peer did not confirm the key"));
        };
        send.finish().map_err(peer_error)?;
        connection.close(0u32.into(), b"done");
        Ok(())
    }

    /// Make a new vault key, give it to every peer, then take it. A peer is missed only when it
    /// still holds the old key: one whose confirmation was lost is asked once more with the new
    /// key before it is listed.
    async fn rotate(&self) -> Result<RotateReport> {
        let _busy = Busy::new(&self.active);
        let old = self.vault().peer_key()?;
        let mut new = [0u8; 32];
        getrandom::fill(&mut new).map_err(peer_error)?;
        let peers = self.vault().peer_list()?;
        let mut report = RotateReport {
            reached: 0,
            missed: Vec::new(),
        };
        for peer in &peers {
            let handed = tokio::time::timeout(SESSION_TIMEOUT, self.hand_over(peer, &old, &new))
                .await
                .map_err(|_| peer_error("a peer did not answer"))
                .and_then(|done| done);
            let outcome = match handed {
                Ok(()) => RotationOutcome::Confirmed,
                Err(_) => RotationOutcome::Probed {
                    holds_key: tokio::time::timeout(SESSION_TIMEOUT, self.holds_key(peer, &new))
                        .await
                        .is_ok_and(|probe| probe.is_ok()),
                },
            };
            self.emit(NodeEvent::KeyRotation {
                id: peer.id.clone(),
                outcome,
            });
            let took = !matches!(outcome, RotationOutcome::Probed { holds_key: false });
            if took {
                report.reached += 1;
            } else {
                self.lost(&peer.id);
                report.missed.push(peer.id.clone());
            }
        }
        let vault = self.vault();
        vault.replace_key(&new)?;
        for id in &report.missed {
            vault.mark_missed(id)?;
        }
        drop(vault);
        self.emit(NodeEvent::RotationDone(report.clone()));
        Ok(report)
    }

    /// Answer one session a peer opened. A peer that cannot seal a message with the vault key is
    /// turned away and learns nothing.
    async fn serve(&self, incoming: Incoming) -> Result<()> {
        let _busy = Busy::new(&self.active);
        let connection = incoming.await.map_err(peer_error)?;
        let remote = connection.remote_id();
        let remote_text = id_text(&remote);
        // A node that was removed is turned away before it is read, key or no key.
        if self.vault().is_denied(&remote_text)? {
            connection.close(1u32.into(), b"not paired");
            return Err(peer_error("a removed peer called"));
        }
        let key = self.vault().peer_key()?;
        let (mut send, mut recv) = connection.accept_bi().await.map_err(peer_error)?;
        let sealed = read_frame(&mut recv, MAX_HELLO).await?;
        let first = match open_frame(&key, Side::Dialer, &sealed) {
            Ok(opened) => Ok(opened),
            Err(err) => {
                // A node without the vault key may be bringing it: the frame opens with the
                // secret of the request this node shows, while the request lasts, and only then.
                let Some((request, given, relay, aside)) = self.take_join(&sealed) else {
                    connection.close(1u32.into(), b"not paired");
                    return Err(err);
                };
                // A vault paired with another vault already keeps its key: refused at once, with
                // nothing put to the person.
                let paired_elsewhere = {
                    let vault = self.vault();
                    vault.peer_key()? != given && !vault.peer_list()?.is_empty()
                };
                if paired_elsewhere {
                    send_message(
                        &mut send,
                        &request.secret,
                        Side::Answerer,
                        &Message::Refused,
                    )
                    .await?;
                    send.finish().map_err(peer_error)?;
                    let _ =
                        tokio::time::timeout(Duration::from_secs(10), connection.closed()).await;
                    return Err(peer_error(
                        "this vault is paired with another vault already",
                    ));
                }
                // The key is kept only when the person at this device says so, told who brought
                // it; until then, and when they refuse, the request is still on show.
                let identity = aside.identity();
                let (answer, asked) = tokio::sync::oneshot::channel();
                *lock(&self.offer) = Some((request.secret, answer));
                self.emit(NodeEvent::JoinOffered {
                    id: remote_text.clone(),
                    kind: identity.kind.clone(),
                    name: identity.name.clone(),
                    words: request.words().to_vec(),
                });
                let kept = matches!(
                    tokio::time::timeout(CONFIRM_TIMEOUT, asked).await,
                    Ok(Ok(true))
                );
                {
                    let mut offer = lock(&self.offer);
                    if offer
                        .as_ref()
                        .is_some_and(|(tag, _)| *tag == request.secret)
                    {
                        *offer = None;
                    }
                }
                if !kept {
                    {
                        let mut slot = lock(&self.request);
                        if slot.is_none() {
                            *slot = Some(request.clone());
                        }
                    }
                    send_message(
                        &mut send,
                        &request.secret,
                        Side::Answerer,
                        &Message::Refused,
                    )
                    .await?;
                    send.finish().map_err(peer_error)?;
                    let _ =
                        tokio::time::timeout(Duration::from_secs(10), connection.closed()).await;
                    return Err(peer_error("the key was refused here"));
                }
                // The phone hears Done first: a key kept after the phone has gone is not kept.
                send_message(&mut send, &request.secret, Side::Answerer, &Message::Done).await?;
                send.finish().map_err(peer_error)?;
                {
                    let vault = self.vault();
                    vault.adopt_key(&given)?;
                    vault.remember_peer(&remote_text, &relay, &[])?;
                    vault.allow(&remote_text)?;
                    vault.note_identity(&remote_text, &identity)?;
                }
                // Connected, but not seen in a session yet: the first sync is the first fetch.
                lock(&self.connected).insert(remote_text.clone());
                self.emit(NodeEvent::PeerJoined {
                    id: remote_text.clone(),
                });
                let _ = tokio::time::timeout(Duration::from_secs(10), connection.closed()).await;
                return Ok(());
            }
        };
        let (theirs, ticket, aside) = match first {
            Ok((Message::Hello { heads, ticket }, aside)) => (heads, ticket, aside),
            Ok((Message::Rotate(new), _)) => {
                // Only a peer this vault knows may change its key.
                if !self.vault().is_peer(&remote_text)? {
                    connection.close(1u32.into(), b"not paired");
                    return Err(peer_error("a stranger sent a new key"));
                }
                self.vault().replace_key(&new)?;
                self.reached(&remote_text);
                if self.dropped_acks.load(Ordering::SeqCst) > 0 {
                    self.dropped_acks.fetch_sub(1, Ordering::SeqCst);
                    connection.close(1u32.into(), b"dropped");
                    return Ok(());
                }
                send_message(&mut send, &key, Side::Answerer, &Message::Done).await?;
                send.finish().map_err(peer_error)?;
                let _ = tokio::time::timeout(Duration::from_secs(10), connection.closed()).await;
                return Ok(());
            }
            Ok((Message::Probe, _)) => {
                if !self.vault().is_peer(&remote_text)? {
                    connection.close(1u32.into(), b"not paired");
                    return Err(peer_error("a stranger sent a probe"));
                }
                send_message(&mut send, &key, Side::Answerer, &Message::Done).await?;
                send.finish().map_err(peer_error)?;
                let _ = tokio::time::timeout(Duration::from_secs(10), connection.closed()).await;
                return Ok(());
            }
            other => {
                connection.close(1u32.into(), b"not paired");
                return other.and(Err(peer_error("a peer opened out of turn")));
            }
        };
        // Proving the key is not enough for a node this vault does not know: it also redeems a
        // ticket this vault issued, once.
        if !self.vault().is_peer(&remote_text)? {
            let redeemed = match ticket {
                Some(id) => self.vault().redeem_ticket(&id, self.ticket_lifetime())?,
                None => false,
            };
            if !redeemed {
                connection.close(1u32.into(), b"not paired");
                return Err(peer_error("a peer has no ticket to redeem"));
            }
            self.emit(NodeEvent::TicketRedeemed {
                by: remote_text.clone(),
            });
        }
        if self.vault().remember_peer(&remote_text, &self.relay, &[])? {
            self.emit(NodeEvent::PeerJoined {
                id: remote_text.clone(),
            });
        }
        self.vault()
            .note_identity(&remote_text, &aside.identity())?;
        let (updates, heads, buds) = {
            // Edits made in the folder since the last look go out with this answer.
            let mut vault = self.vault();
            vault.rescan()?;
            vault.sync()?;
            (
                vault.updates_for(&theirs)?,
                vault.heads()?,
                vault.bud_count()?,
            )
        };
        send_with_aside(
            &mut send,
            &key,
            Side::Answerer,
            &Message::Reply { updates, heads },
            &Aside::new(&self.identity, Some(buds)),
        )
        .await?;
        let Message::Final(updates) =
            read_message(&mut recv, &key, Side::Dialer, MAX_FRAME).await?
        else {
            return Err(peer_error("a peer sent out of turn"));
        };
        let report = self.vault().apply_updates(&updates)?;
        send_message(&mut send, &key, Side::Answerer, &Message::Done).await?;
        send.finish().map_err(peer_error)?;
        self.reached(&id_text(&remote));
        if report.changed() {
            self.emit(NodeEvent::SyncFinished(report));
        }
        let _ = tokio::time::timeout(Duration::from_secs(10), connection.closed()).await;
        Ok(())
    }
}

/// The transport of one open vault: an endpoint that finds its peers on the local network and
/// syncs with them.
pub struct Node {
    runtime: Option<Runtime>,
    shared: Arc<Shared>,
}

impl Node {
    /// Start with the default options for `relay`: look at the folder and sync with every peer
    /// every few seconds.
    pub fn start(vault: Arc<Mutex<Vault>>, relay: Relay) -> Result<Node> {
        Node::start_with(vault, NodeOptions::new(relay))
    }

    pub fn start_with(vault: Arc<Mutex<Vault>>, options: NodeOptions) -> Result<Node> {
        let index_dir = {
            let vault = lock(&vault);
            vault.peer_key()?;
            vault.index_dir.clone()
        };
        let secret = node_key(&index_dir.join(NODE_KEY_FILE))?;
        options.relay.url()?;
        let runtime = tokio::runtime::Builder::new_multi_thread()
            .worker_threads(2)
            .thread_name("bud-peer")
            .enable_all()
            .build()?;
        let endpoint = runtime.block_on(bind(secret, &options.relay))?;
        let shared = Arc::new(Shared {
            endpoint,
            vault,
            relay: options.relay,
            connected: Mutex::new(HashSet::new()),
            active: AtomicUsize::new(0),
            ticket_lifetime_ms: AtomicU64::new(TICKET_LIFETIME.as_millis() as u64),
            dropped_acks: AtomicUsize::new(0),
            identity: options.identity,
            listeners: Mutex::new(Vec::new()),
            request: Mutex::new(None),
            offer: Mutex::new(None),
        });
        let accepting = Arc::clone(&shared);
        runtime.spawn(async move {
            let sessions = Arc::new(tokio::sync::Semaphore::new(MAX_SESSIONS));
            while let Some(incoming) = accepting.endpoint.accept().await {
                // Over the limit a caller is refused, not queued: a stranger cannot fill it.
                let Ok(permit) = Arc::clone(&sessions).try_acquire_owned() else {
                    incoming.refuse();
                    continue;
                };
                let serving = Arc::clone(&accepting);
                tokio::spawn(async move {
                    let _ = tokio::time::timeout(SESSION_TIMEOUT, serving.serve(incoming)).await;
                    drop(permit);
                });
            }
        });
        if let Some(interval) = options.interval {
            let syncing = Arc::clone(&shared);
            runtime.spawn(async move {
                loop {
                    tokio::time::sleep(interval).await;
                    let _ = syncing.sync_all().await;
                }
            });
        }
        Ok(Node {
            runtime: Some(runtime),
            shared,
        })
    }

    fn runtime(&self) -> Result<&Runtime> {
        self.runtime
            .as_ref()
            .ok_or_else(|| peer_error("the node is closed"))
    }

    /// This node's id in hex.
    pub fn id(&self) -> String {
        id_text(&self.shared.endpoint.id())
    }

    /// A ticket for another device on any network: node id, relay setting and vault key.
    pub fn ticket(&self) -> Result<Ticket> {
        let vault = self.shared.vault();
        Ok(Ticket {
            node: *self.shared.endpoint.id().as_bytes(),
            id: vault.issue_ticket(self.shared.ticket_lifetime())?,
            relay: self.shared.relay.clone(),
            key: vault.peer_key()?,
            addrs: Vec::new(),
        })
    }

    /// Change how long a ticket made from now on can be redeemed; ten minutes by default. For
    /// tests, which cannot wait that long.
    #[doc(hidden)]
    pub fn set_ticket_lifetime(&self, lifetime: Duration) {
        self.shared
            .ticket_lifetime_ms
            .store(lifetime.as_millis() as u64, Ordering::SeqCst);
    }

    /// Withhold the confirmation of the next `count` key hand overs this node answers, after it
    /// took the key. For tests of a lost acknowledgement.
    #[doc(hidden)]
    pub fn drop_next_key_acks(&self, count: usize) {
        self.shared.dropped_acks.store(count, Ordering::SeqCst);
    }

    /// The same ticket with the addresses this node listens on, loopback included. Longer, for a
    /// peer that cannot look the node up.
    pub fn ticket_with_addresses(&self) -> Result<Ticket> {
        let mut ticket = self.ticket()?;
        ticket.addrs = self.shared.listen_addrs();
        Ok(ticket)
    }

    /// Show a join request: a code for a device that holds the vault to scan, and six words.
    /// It replaces the one shown before, lasts as long as a ticket, and is good once.
    pub fn join_request(&self) -> Result<JoinRequest> {
        let mut secret = [0u8; 32];
        getrandom::fill(&mut secret).map_err(peer_error)?;
        let request = JoinRequest {
            node: *self.shared.endpoint.id().as_bytes(),
            secret,
            issued: now_millis(),
            relay: self.shared.relay.clone(),
            addrs: self.shared.listen_addrs(),
        };
        *lock(&self.shared.request) = Some(request.clone());
        Ok(request)
    }

    /// Read a join request another device shows, to put its six words to the person. Nothing
    /// moves until [`Node::confirm_request`]. A request of this node's own, or one past its
    /// lifetime, is refused here.
    pub fn read_request(&self, text: &str) -> Result<JoinRequest> {
        let request = JoinRequest::parse(text)?;
        let id = PublicKey::from_bytes(&request.node).map_err(peer_error)?;
        if id == self.shared.endpoint.id() {
            return Err(Error::Invalid(
                "peer: that request is this vault's".to_string(),
            ));
        }
        request.relay.url()?;
        if request.is_expired(self.shared.ticket_lifetime(), now_millis()) {
            return Err(Error::Invalid(
                "peer: that request is past its lifetime".to_string(),
            ));
        }
        Ok(request)
    }

    /// The person confirmed the six words: bring this vault's key to the device that showed the
    /// request and remember it as a peer. Do not call it from inside an async runtime.
    pub fn confirm_request(&self, request: &JoinRequest) -> Result<PeerInfo> {
        let request = self.read_request(&request.encode())?;
        let peer = PeerInfo {
            id: request.id(),
            relay: request.relay.clone(),
            addrs: request.addrs.clone(),
            last_seen: None,
            missed: false,
            kind: None,
            name: None,
            label: None,
        };
        if self.shared.vault().is_peer(&peer.id)? {
            return Err(Error::Exists(peer.id));
        }
        let shared = &self.shared;
        self.runtime()?.block_on(async {
            tokio::time::timeout(SESSION_TIMEOUT, shared.offer(&request))
                .await
                .map_err(|_| peer_error("the device did not answer"))
                .and_then(|done| done)
        })?;
        {
            let vault = self.shared.vault();
            vault.remember_peer(&peer.id, &peer.relay, &peer.addrs)?;
            vault.allow(&peer.id)?;
        }
        self.shared.reached(&peer.id);
        self.shared.emit(NodeEvent::PeerJoined {
            id: peer.id.clone(),
        });
        Ok(peer)
    }

    /// The person at this device answered the key on offer, told by [`NodeEvent::JoinOffered`]:
    /// `keep` takes it and makes the node that brought it a peer; otherwise it is turned away and
    /// the request stays on show. Nothing is on offer after the session that brought it ends.
    pub fn answer_join(&self, keep: bool) -> Result<()> {
        let (_, answer) = lock(&self.shared.offer)
            .take()
            .ok_or_else(|| Error::Invalid("peer: no key is on offer".to_string()))?;
        answer
            .send(keep)
            .map_err(|_| Error::Invalid("peer: the offer is over".to_string()))
    }

    /// Accept a ticket from another vault: remember its peer and take its vault key. A peer is
    /// accepted once; a vault that is paired with another vault already refuses a ticket of a
    /// third.
    pub fn accept_ticket(&self, text: &str) -> Result<PeerInfo> {
        let ticket = Ticket::parse(text)?;
        let id = PublicKey::from_bytes(&ticket.node).map_err(peer_error)?;
        if id == self.shared.endpoint.id() {
            return Err(Error::Invalid(
                "peer: that ticket is this vault's".to_string(),
            ));
        }
        ticket.relay.url()?;
        let peer = PeerInfo {
            id: id_text(&id),
            relay: ticket.relay.clone(),
            addrs: ticket.addrs.clone(),
            last_seen: None,
            missed: false,
            kind: None,
            name: None,
            label: None,
        };
        let vault = self.shared.vault();
        if vault.peer_list()?.iter().any(|known| known.id == peer.id) {
            return Err(Error::Exists(peer.id));
        }
        vault.adopt_key(&ticket.key)?;
        vault.remember_peer(&peer.id, &peer.relay, &peer.addrs)?;
        vault.keep_pending_ticket(&peer.id, &ticket.id)?;
        // Taking a ticket of a vault this one removed earlier is a new pairing.
        vault.allow(&peer.id)?;
        Ok(peer)
    }

    /// Lift the refusal of a node this vault removed, so it can redeem a new ticket.
    pub fn allow_peer(&self, id: &str) -> Result<()> {
        self.shared.vault().allow(id)
    }

    /// Make a new vault key and give it to every peer over the existing sessions. Tickets made
    /// before it stop working, and so does the old key. Do not call it from inside an async
    /// runtime.
    pub fn rotate_key(&self) -> Result<RotateReport> {
        self.runtime()?.block_on(self.shared.rotate())
    }

    pub fn peers(&self) -> Result<Vec<PeerInfo>> {
        self.shared.vault().peer_list()
    }

    /// Hear every [`NodeEvent`] from now on, on the node's own threads, until the node closes.
    pub fn listen(&self, listener: Box<dyn NodeListener>) {
        lock(&self.shared.listeners).push(listener);
    }

    /// Give a peer a label of this vault's own, shown instead of the name it sends; none or an
    /// empty one takes it away. An error for a node this vault does not know.
    pub fn rename_peer(&self, id: &str, label: Option<&str>) -> Result<()> {
        self.shared.vault().label_peer(id, label)
    }

    /// Forget a peer by its id. It is no longer synced with and is refused from now on, even when
    /// it proves the vault key, until [`Node::allow_peer`] lifts that.
    pub fn forget_peer(&self, id: &str) -> Result<()> {
        self.shared.vault().forget(id)?;
        self.shared.lost(id);
        Ok(())
    }

    /// Whether a sync is running, how many peers the last session reached, and how many files wait
    /// to be synced. A peer that only dials this node counts as connected until a dial to it
    /// fails.
    pub fn state(&self) -> Result<NodeState> {
        let pending = {
            let mut vault = self.shared.vault();
            vault.rescan()?;
            vault.pending_changes()?
        };
        Ok(NodeState {
            syncing: self.shared.active.load(Ordering::SeqCst) > 0,
            connected: lock(&self.shared.connected).len(),
            pending,
        })
    }

    /// Look at the folder, then exchange changes with every peer and wait for it. Do not call it
    /// from inside an async runtime.
    pub fn sync_now(&self) -> Result<SyncReport> {
        self.runtime()?.block_on(self.shared.sync_all())
    }

    /// Stop the endpoint.
    pub fn close(self) {}
}

impl Drop for Node {
    fn drop(&mut self) {
        if let Some(runtime) = self.runtime.take() {
            runtime.block_on(self.shared.endpoint.close());
            runtime.shutdown_timeout(Duration::from_secs(2));
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_sealed_message_is_ciphertext_and_opens_only_with_its_key() {
        let key = [5u8; 32];
        let plain = b"Warm, not corporate. A scarf for the printer.";
        let sealed = seal(&key, Side::Dialer, plain).unwrap();
        assert!(!sealed
            .windows(plain.len().min(8))
            .any(|w| plain.windows(w.len()).any(|p| p == w)));
        assert_eq!(open(&key, Side::Dialer, &sealed).unwrap(), plain);
        assert!(open(&[6u8; 32], Side::Dialer, &sealed).is_err());
        let mut changed = sealed.clone();
        *changed.last_mut().unwrap() ^= 1;
        assert!(open(&key, Side::Dialer, &changed).is_err());
        assert!(
            open(&key, Side::Answerer, &sealed).is_err(),
            "not the other way"
        );
        assert_ne!(
            seal(&key, Side::Dialer, plain).unwrap(),
            sealed,
            "a fresh nonce each time"
        );
    }

    #[test]
    fn a_frame_carries_the_identity_after_the_message_and_reads_without_it() {
        let hello = Message::Hello {
            heads: Heads::default(),
            ticket: None,
        };
        let who = Identity::new("tv", "Living room");
        let aside = Aside::new(&who, Some(1380));
        let with = encode(&hello, &aside).unwrap();
        let without = encode(&hello, &Aside::default()).unwrap();
        assert!(with.len() > without.len());
        // A newer build reads both halves.
        let (message, read) = decode(&with).unwrap();
        assert!(matches!(message, Message::Hello { .. }));
        assert_eq!(read, aside);
        assert_eq!(read.identity(), who);
        // A frame from a build that says nothing reads as no aside.
        assert_eq!(decode(&without).unwrap().1, Aside::default());
        // An older build reads the message alone and ignores the trailer.
        let old: Message = postcard::from_bytes(&with).unwrap();
        assert!(matches!(old, Message::Hello { .. }));
        // A build that sent the identity alone, before the bud count, still reads.
        let mut identity_only = postcard::to_stdvec(&hello).unwrap();
        identity_only.extend(postcard::to_stdvec(&who).unwrap());
        let read = decode(&identity_only).unwrap().1;
        assert_eq!(read.identity(), who);
        assert_eq!(read.buds, None);
        // A trailer that is neither is treated as none, not as an error.
        let mut odd = without.clone();
        odd.extend_from_slice(&[0xff, 0xff, 0xff]);
        assert_eq!(decode(&odd).unwrap().1, Aside::default());
    }
}
