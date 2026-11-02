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
use crate::{Error, Result, SyncReport, Vault};
use chacha20poly1305::aead::{Aead, KeyInit, Payload};
use chacha20poly1305::{XChaCha20Poly1305, XNonce};
use data_encoding::{BASE32_NOPAD, HEXLOWER};
use iroh::endpoint::{presets, Incoming};
use iroh::{Endpoint, EndpointAddr, PublicKey, RelayMode, RelayUrl, SecretKey};
use iroh_mdns_address_lookup::MdnsAddressLookup;
use rusqlite::{params, OptionalExtension};
use serde::{Deserialize, Serialize};
use std::net::{IpAddr, Ipv4Addr, Ipv6Addr, SocketAddr};
use std::path::Path;
use std::str::FromStr;
use std::sync::{Arc, Mutex, MutexGuard};
use std::time::{Duration, SystemTime, UNIX_EPOCH};
use tokio::runtime::Runtime;

/// The protocol name two nodes agree on when they connect.
const ALPN: &[u8] = b"bud/sync/1";
/// The service name under which nodes announce themselves on the local network.
const MDNS_SERVICE: &str = "bud";
/// A ticket string starts with this, then the base32 of its fields.
const TICKET_PREFIX: &str = "bud1";
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
const DEFAULT_INTERVAL: Duration = Duration::from_secs(5);

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
    pub relay: Relay,
    pub key: [u8; 32],
    pub addrs: Vec<SocketAddr>,
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
        // Upper case lets the code use its denser alphanumeric mode; `parse` ignores case.
        let code = qrcode::QrCode::new(self.encode().to_ascii_uppercase().as_bytes())
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
}

/// A peer this vault remembers.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PeerInfo {
    /// The node id in hex.
    pub id: String,
    pub relay: Relay,
    pub addrs: Vec<SocketAddr>,
}

/// How a node starts.
#[derive(Debug, Clone)]
pub struct NodeOptions {
    pub relay: Relay,
    /// How often to look at the folder and sync with every peer; none leaves it to
    /// [`Node::sync_now`].
    pub interval: Option<Duration>,
}

impl NodeOptions {
    pub fn new(relay: Relay) -> NodeOptions {
        NodeOptions {
            relay,
            interval: Some(DEFAULT_INTERVAL),
        }
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

    fn peer_list(&self) -> Result<Vec<PeerInfo>> {
        let conn = lock(&self.conn);
        let mut stmt = conn.prepare("SELECT node, relay, addrs FROM peers ORDER BY added, node")?;
        let rows = stmt.query_map([], |r| {
            Ok((
                r.get::<_, String>(0)?,
                r.get::<_, String>(1)?,
                r.get::<_, String>(2)?,
            ))
        })?;
        let mut peers = Vec::new();
        for row in rows {
            let (id, relay, addrs) = row?;
            peers.push(PeerInfo {
                id,
                relay: Relay::from_text(&relay),
                addrs: addrs.lines().filter_map(|a| a.parse().ok()).collect(),
            });
        }
        Ok(peers)
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
    Hello(Heads),
    Reply { updates: Updates, heads: Heads },
    Final(Updates),
    Done,
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

async fn send_message(
    send: &mut iroh::endpoint::SendStream,
    key: &[u8; 32],
    from: Side,
    message: &Message,
) -> Result<()> {
    let plain = postcard::to_stdvec(message).map_err(peer_error)?;
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
    postcard::from_bytes(&open(key, from, &sealed)?).map_err(peer_error)
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
}

impl Shared {
    fn vault(&self) -> MutexGuard<'_, Vault> {
        lock(&self.vault)
    }

    /// Look at the folder, then sync with every peer. An error only when no peer could be synced.
    async fn sync_all(&self) -> Result<SyncReport> {
        let mut report = {
            let mut vault = self.vault();
            vault.rescan()?;
            vault.sync()?
        };
        let peers = self.vault().peer_list()?;
        let mut failure = None;
        let mut reached = false;
        for peer in &peers {
            match tokio::time::timeout(SESSION_TIMEOUT, self.exchange(peer)).await {
                Ok(Ok(done)) => {
                    report.add(done);
                    reached = true;
                }
                Ok(Err(err)) => failure = failure.or(Some(err)),
                Err(_) => failure = failure.or(Some(peer_error("a peer did not answer"))),
            }
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
        let heads = self.vault().heads()?;
        send_message(&mut send, &key, Side::Dialer, &Message::Hello(heads)).await?;
        let Message::Reply { updates, heads } =
            read_message(&mut recv, &key, Side::Answerer, MAX_FRAME).await?
        else {
            return Err(peer_error("a peer answered out of turn"));
        };
        let report = self.vault().apply_updates(&updates)?;
        let mine = self.vault().updates_for(&heads)?;
        send_message(&mut send, &key, Side::Dialer, &Message::Final(mine)).await?;
        let Message::Done = read_message(&mut recv, &key, Side::Answerer, MAX_FRAME).await? else {
            return Err(peer_error("a peer did not confirm"));
        };
        send.finish().map_err(peer_error)?;
        connection.close(0u32.into(), b"done");
        Ok(report)
    }

    /// Answer one session a peer opened. A peer that cannot seal a message with the vault key is
    /// turned away and learns nothing.
    async fn serve(&self, incoming: Incoming) -> Result<()> {
        let connection = incoming.await.map_err(peer_error)?;
        let remote = connection.remote_id();
        let key = self.vault().peer_key()?;
        let (mut send, mut recv) = connection.accept_bi().await.map_err(peer_error)?;
        let theirs = match read_message(&mut recv, &key, Side::Dialer, MAX_HELLO).await {
            Ok(Message::Hello(heads)) => heads,
            other => {
                connection.close(1u32.into(), b"not paired");
                return other.and(Err(peer_error("a peer opened out of turn")));
            }
        };
        // It proved it holds the vault key: it is a peer.
        self.vault()
            .remember_peer(&id_text(&remote), &self.relay, &[])?;
        let (updates, heads) = {
            // Edits made in the folder since the last look go out with this answer.
            let mut vault = self.vault();
            vault.rescan()?;
            vault.sync()?;
            (vault.updates_for(&theirs)?, vault.heads()?)
        };
        send_message(
            &mut send,
            &key,
            Side::Answerer,
            &Message::Reply { updates, heads },
        )
        .await?;
        let Message::Final(updates) =
            read_message(&mut recv, &key, Side::Dialer, MAX_FRAME).await?
        else {
            return Err(peer_error("a peer sent out of turn"));
        };
        self.vault().apply_updates(&updates)?;
        send_message(&mut send, &key, Side::Answerer, &Message::Done).await?;
        send.finish().map_err(peer_error)?;
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
        Ok(Ticket {
            node: *self.shared.endpoint.id().as_bytes(),
            relay: self.shared.relay.clone(),
            key: self.shared.vault().peer_key()?,
            addrs: Vec::new(),
        })
    }

    /// The same ticket with the addresses this node listens on, loopback included. Longer, for a
    /// peer that cannot look the node up.
    pub fn ticket_with_addresses(&self) -> Result<Ticket> {
        let mut ticket = self.ticket()?;
        let endpoint = &self.shared.endpoint;
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
        ticket.addrs = addrs;
        Ok(ticket)
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
        };
        let vault = self.shared.vault();
        if vault.peer_list()?.iter().any(|known| known.id == peer.id) {
            return Err(Error::Exists(peer.id));
        }
        vault.adopt_key(&ticket.key)?;
        vault.remember_peer(&peer.id, &peer.relay, &peer.addrs)?;
        Ok(peer)
    }

    pub fn peers(&self) -> Result<Vec<PeerInfo>> {
        self.shared.vault().peer_list()
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
}
