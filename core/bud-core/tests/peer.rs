//! The peer transport: two vaults in one process pair with a ticket and exchange documents over
//! the loopback interface, with the relay off.

mod common;

use bud_core::{
    Identity, JoinRequest, Node, NodeEvent, NodeListener, NodeOptions, Relay, RotationOutcome,
    Ticket, Vault,
};
use common::{copy_dir, fingerprint, fixture};
use pretty_assertions::assert_eq;
use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

struct Peer {
    vault: Arc<Mutex<Vault>>,
    dir: tempfile::TempDir,
    index: tempfile::TempDir,
    node: Node,
}

impl Peer {
    fn new(seed: Option<&Path>, interval: Option<Duration>) -> Peer {
        Peer::new_as(seed, interval, Identity::default())
    }

    fn new_as(seed: Option<&Path>, interval: Option<Duration>, identity: Identity) -> Peer {
        let dir = tempfile::tempdir().unwrap();
        if let Some(seed) = seed {
            copy_dir(seed, dir.path());
        }
        let index = tempfile::tempdir().unwrap();
        let vault = Vault::open(dir.path(), index.path().join("index.db")).unwrap();
        let vault = Arc::new(Mutex::new(vault));
        let options = NodeOptions {
            relay: Relay::Off,
            interval,
            identity,
        };
        let node = Node::start_with(Arc::clone(&vault), options).unwrap();
        Peer {
            vault,
            dir,
            index,
            node,
        }
    }

    /// The same vault and index under a node that says something else about itself.
    fn restart_as(self, identity: Identity) -> Peer {
        let Peer {
            vault,
            dir,
            index,
            node,
        } = self;
        drop(node);
        let options = NodeOptions {
            relay: Relay::Off,
            interval: None,
            identity,
        };
        let node = Node::start_with(Arc::clone(&vault), options).unwrap();
        Peer {
            vault,
            dir,
            index,
            node,
        }
    }

    fn path(&self, name: &str) -> PathBuf {
        self.dir.path().join(name)
    }

    fn read(&self, name: &str) -> Option<String> {
        std::fs::read_to_string(self.path(name)).ok()
    }

    fn write(&self, name: &str, text: &str) {
        std::fs::write(self.path(name), text).unwrap();
    }
}

/// Keeps every event a node tells, in order.
#[derive(Clone, Default)]
struct Recorder(Arc<Mutex<Vec<NodeEvent>>>);

impl Recorder {
    fn listening(node: &Node) -> Recorder {
        let recorder = Recorder::default();
        node.listen(Box::new(recorder.clone()));
        recorder
    }

    fn events(&self) -> Vec<NodeEvent> {
        self.0.lock().unwrap().clone()
    }
}

impl NodeListener for Recorder {
    fn event(&self, event: NodeEvent) {
        self.0.lock().unwrap().push(event);
    }
}

fn eventually(what: &str, mut check: impl FnMut() -> bool) {
    let start = Instant::now();
    while start.elapsed() < Duration::from_secs(8) {
        if check() {
            return;
        }
        std::thread::sleep(Duration::from_millis(100));
    }
    panic!("not within a few seconds: {what}");
}

/// `a` holds the fixture vault, `b` an empty folder that accepted a's ticket.
fn paired(interval: Option<Duration>) -> (Peer, Peer) {
    let a = Peer::new(Some(&fixture()), None);
    let b = Peer::new(None, interval);
    a.node.sync_now().unwrap();
    let ticket = a.node.ticket_with_addresses().unwrap().encode();
    b.node.accept_ticket(&ticket).unwrap();
    (a, b)
}

#[test]
fn a_ticket_is_a_short_string_that_round_trips() {
    let ticket = Ticket {
        node: [10; 32],
        id: [4; 16],
        relay: Relay::Custom("https://relay.example.org/".to_string()),
        key: [7; 32],
        addrs: vec![],
    };
    let text = ticket.encode();
    assert!(text.starts_with("bud1"), "{text}");
    assert!(text.len() < 200, "{}", text.len());
    assert!(text.chars().all(|c| c.is_ascii_alphanumeric()));
    assert_eq!(Ticket::parse(&text).unwrap(), ticket);
    assert_eq!(Ticket::parse(&text.to_uppercase()).unwrap(), ticket);
    for relay in [Relay::Default, Relay::Off] {
        let ticket = Ticket {
            relay,
            ..ticket.clone()
        };
        assert_eq!(Ticket::parse(&ticket.encode()).unwrap(), ticket);
    }
}

#[test]
fn a_damaged_ticket_is_refused() {
    let ticket = Ticket {
        node: [11; 32],
        id: [5; 16],
        relay: Relay::Off,
        key: [1; 32],
        addrs: vec![],
    };
    let text = ticket.encode();
    assert!(Ticket::parse("").is_err());
    assert!(Ticket::parse("hello").is_err());
    assert!(Ticket::parse(&text[..text.len() - 6]).is_err());
    assert!(Ticket::parse(&text.replacen("bud1", "bud2", 1)).is_err());
}

#[test]
fn a_ticket_is_the_content_of_a_qr_code() {
    let ticket = Ticket {
        node: [12; 32],
        id: [6; 16],
        relay: Relay::Default,
        key: [9; 32],
        addrs: vec![],
    };
    let code = ticket.qr().unwrap();
    assert!(code.width >= 21);
    assert_eq!(code.dark.len(), code.width * code.width);
    assert!(code.dark.iter().any(|d| *d) && code.dark.iter().any(|d| !*d));
}

#[test]
fn a_node_keeps_its_key_next_to_the_index() {
    let dir = tempfile::tempdir().unwrap();
    let index = tempfile::tempdir().unwrap();
    let open = || {
        let vault = Vault::open(dir.path(), index.path().join("index.db")).unwrap();
        Node::start_with(
            Arc::new(Mutex::new(vault)),
            NodeOptions {
                relay: Relay::Off,
                interval: None,
                identity: Identity::default(),
            },
        )
        .unwrap()
    };
    let first = open();
    let id = first.id();
    let key = first.ticket().unwrap().key;
    first.close();
    let again = open();
    assert_eq!(again.id(), id);
    assert_eq!(again.ticket().unwrap().key, key);
    assert!(index.path().join("node.key").is_file());
    assert_eq!(std::fs::read_dir(dir.path()).unwrap().count(), 0);
}

#[test]
fn an_edit_on_one_vault_appears_in_the_other() {
    let (a, b) = paired(None);
    let summary = b.node.sync_now().unwrap();
    assert!(summary.created > 0, "{summary:?}");

    // The whole fixture arrived, in its places, with its text.
    for name in [
        "Gift ideas.md",
        "Launch the newsletter.md",
        "Launch the newsletter/Pick a name.md",
        "Launch the newsletter/Pick a name/Shortlist three candidates.md",
        "Routines/Weekly review.md",
    ] {
        assert_eq!(b.read(name), a.read(name), "{name}");
    }

    let name = "Launch the newsletter/Design notes.md";
    let edited = format!("{}\nCheck the footer.\n", a.read(name).unwrap().trim_end());
    a.write(name, &edited);
    a.node.sync_now().unwrap();
    b.node.sync_now().unwrap();
    eventually("the edit reaches b", || {
        b.read(name) == Some(edited.clone())
    });
}

#[test]
fn an_edit_made_on_the_second_vault_reaches_the_first() {
    let (a, b) = paired(None);
    b.node.sync_now().unwrap();
    let name = "Gift ideas.md";
    let edited = format!("{}A scarf.\n", b.read(name).unwrap());
    b.write(name, &edited);
    b.node.sync_now().unwrap();
    eventually("the edit reaches a", || {
        a.read(name) == Some(edited.clone())
    });
}

#[test]
fn a_vault_syncs_on_its_own_while_it_runs() {
    let (a, b) = paired(Some(Duration::from_millis(300)));
    eventually("the folder arrives", || b.read("Gift ideas.md").is_some());
    let name = "Gift ideas.md";
    let edited = format!("{}Candles.\n", a.read(name).unwrap());
    a.write(name, &edited);
    eventually("the edit arrives", || b.read(name) == Some(edited.clone()));
}

#[test]
fn a_peer_and_a_ticket_live_in_the_index_folder_only() {
    let (a, b) = paired(None);
    b.node.sync_now().unwrap();
    assert!(b.index.path().join("node.key").is_file());
    assert!(a.index.path().join("node.key").is_file());
    let before = fingerprint(a.dir.path());
    let peers = b.node.peers().unwrap();
    assert_eq!(peers.len(), 1);
    assert_eq!(peers[0].id, a.node.id());
    assert_eq!(a.node.peers().unwrap().len(), 1, "a learns b by its proof");
    for peer in [&a, &b] {
        let found = fingerprint(peer.dir.path());
        assert!(found.keys().all(|k| !k.contains("node.key")), "{found:?}");
        assert!(found.keys().all(|k| !k.contains("index.db")), "{found:?}");
    }
    assert_eq!(fingerprint(a.dir.path()), before);
}

#[test]
fn a_ticket_is_accepted_once() {
    let a = Peer::new(Some(&fixture()), None);
    let b = Peer::new(None, None);
    let ticket = a.node.ticket_with_addresses().unwrap().encode();
    let peer = b.node.accept_ticket(&ticket).unwrap();
    assert_eq!(peer.id, a.node.id());
    assert!(matches!(
        b.node.accept_ticket(&ticket),
        Err(bud_core::Error::Exists(_))
    ));
    assert_eq!(b.node.peers().unwrap().len(), 1);
    // The vault key is the one of the ticket now.
    assert_eq!(b.node.ticket().unwrap().key, a.node.ticket().unwrap().key);
}

#[test]
fn a_node_that_is_not_paired_learns_nothing() {
    let a = Peer::new(Some(&fixture()), None);
    let stranger = Peer::new(None, None);
    a.node.sync_now().unwrap();
    // A ticket made from the stranger's own key but pointing at a: it opens the door to nothing.
    let mut ticket = a.node.ticket_with_addresses().unwrap();
    ticket.key = [3; 32];
    stranger.node.accept_ticket(&ticket.encode()).unwrap();
    assert!(stranger.node.sync_now().is_err());
    assert_eq!(stranger.read("Gift ideas.md"), None);
    assert!(a.node.peers().unwrap().is_empty());
}

#[test]
fn a_folder_bud_on_one_vault_comes_back_unchanged() {
    let a = Peer::new(Some(&fixture()), None);
    std::fs::create_dir(a.path("Loose folder")).unwrap();
    a.write("Loose folder/Child note.md", "A note in a folder.\n");
    let b = Peer::new(None, None);
    a.node.sync_now().unwrap();
    let before = fingerprint(a.dir.path());
    b.node
        .accept_ticket(&a.node.ticket_with_addresses().unwrap().encode())
        .unwrap();
    for _ in 0..2 {
        b.node.sync_now().unwrap();
        a.node.sync_now().unwrap();
    }
    assert_eq!(
        b.read("Loose folder/Child note.md").as_deref(),
        Some("A note in a folder.\n")
    );
    assert_eq!(fingerprint(a.dir.path()), before);
    // A bud in the trash does not travel to a vault that has none of it.
    let count = |p: &Peer| {
        let buds = p.vault.lock().unwrap().all().unwrap();
        buds.iter()
            .filter(|b| b.place != bud_core::Place::Trash)
            .count()
    };
    assert_eq!(count(&a), count(&b));
}

#[test]
fn every_frontmatter_key_reaches_the_other_vault() {
    let (a, b) = paired(None);
    b.node.sync_now().unwrap();
    let name = "Launch the newsletter/Design notes.md";
    assert_eq!(b.read(name), a.read(name));
    assert!(b.read(name).unwrap().contains("tags: [brand]\ncreated:"));
}

#[test]
fn unknown_keys_arrive_in_the_senders_order() {
    let a = Peer::new(Some(&fixture()), None);
    let name = "Gift ideas.md";
    let text = "---\nzeta: 1\nstate: open\naliases:\n  - Mail\n  # kept\nalpha: [x, 'y']\nsource: phone\n---\nBody\n";
    a.write(name, text);
    let b = Peer::new(None, None);
    a.node.sync_now().unwrap();
    b.node
        .accept_ticket(&a.node.ticket_with_addresses().unwrap().encode())
        .unwrap();
    b.node.sync_now().unwrap();
    assert_eq!(b.read(name), a.read(name));
    // An edit of an unknown key on the second vault comes back to the first.
    let edited = text.replace("alpha: [x, 'y']", "alpha: [z]");
    b.write(name, &edited);
    b.node.sync_now().unwrap();
    a.node.sync_now().unwrap();
    eventually("the key edit reaches a", || {
        a.read(name) == Some(edited.clone())
    });
}

#[test]
fn a_removed_peer_cannot_sync_even_with_the_key() {
    let (a, b) = paired(None);
    b.node.sync_now().unwrap();
    assert_eq!(a.node.peers().unwrap().len(), 1);
    a.node.forget_peer(&b.node.id()).unwrap();
    assert!(a.node.peers().unwrap().is_empty());
    // b still holds the vault key and still lists a, but a turns it away.
    let edited = format!("{}A scarf.\n", a.read("Gift ideas.md").unwrap());
    a.write("Gift ideas.md", &edited);
    a.node.sync_now().unwrap();
    assert!(b.node.sync_now().is_err());
    assert_ne!(b.read("Gift ideas.md"), Some(edited));
    assert!(a.node.peers().unwrap().is_empty(), "not learned again");
}

#[test]
fn a_removed_peer_is_paired_again_with_a_fresh_ticket() {
    let (a, b) = paired(None);
    b.node.sync_now().unwrap();
    a.node.forget_peer(&b.node.id()).unwrap();
    assert!(b.node.sync_now().is_err());
    let ticket = a.node.ticket_with_addresses().unwrap().encode();
    b.node.forget_peer(&a.node.id()).unwrap();
    b.node.accept_ticket(&ticket).unwrap();
    // The maker still refuses a node it removed; only the maker can lift that.
    assert!(b.node.sync_now().is_err());
    a.node.allow_peer(&b.node.id()).unwrap();
    b.node.sync_now().unwrap();
    assert_eq!(a.node.peers().unwrap().len(), 1);
}

#[test]
fn rotating_the_key_moves_the_remaining_peers_and_turns_the_old_key_away() {
    let a = Peer::new(Some(&fixture()), None);
    let b = Peer::new(None, None);
    let c = Peer::new(None, None);
    a.node.sync_now().unwrap();
    for p in [&b, &c] {
        p.node
            .accept_ticket(&a.node.ticket_with_addresses().unwrap().encode())
            .unwrap();
        p.node.sync_now().unwrap();
    }
    let old = a.node.ticket().unwrap().key;
    // A ticket made before the rotation.
    let stale = a.node.ticket_with_addresses().unwrap().encode();
    a.node.forget_peer(&c.node.id()).unwrap();
    let report = a.node.rotate_key().unwrap();
    assert_eq!(report.reached, 1);
    let new = a.node.ticket().unwrap().key;
    assert_ne!(new, old);
    assert_eq!(b.node.ticket().unwrap().key, new, "b got the new key");
    assert_eq!(c.node.ticket().unwrap().key, old, "c did not");
    // b keeps syncing.
    let edited = format!("{}Candles.\n", a.read("Gift ideas.md").unwrap());
    a.write("Gift ideas.md", &edited);
    a.node.sync_now().unwrap();
    b.node.sync_now().unwrap();
    eventually("the edit reaches b", || {
        b.read("Gift ideas.md") == Some(edited.clone())
    });
    assert!(c.node.sync_now().is_err(), "the old key is turned away");
    // A ticket of before the rotation does not pair a new vault.
    let d = Peer::new(None, None);
    d.node.accept_ticket(&stale).unwrap();
    assert!(d.node.sync_now().is_err());
    assert_eq!(d.read("Gift ideas.md"), None);
}

#[test]
fn the_maker_hears_who_redeemed_its_ticket_and_the_taker_hears_the_size_of_the_fetch() {
    let a = Peer::new(Some(&fixture()), None);
    let b = Peer::new(None, None);
    a.node.sync_now().unwrap();
    let heard_by_a = Recorder::listening(&a.node);
    let heard_by_b = Recorder::listening(&b.node);
    let total = a.vault.lock().unwrap().bud_count().unwrap();
    assert!(total > 0);
    b.node
        .accept_ticket(&a.node.ticket_with_addresses().unwrap().encode())
        .unwrap();
    assert_eq!(heard_by_a.events(), vec![], "nothing happens until b dials");
    b.node.sync_now().unwrap();
    // a hears the ticket go, and the new peer, before its answer leaves.
    assert_eq!(
        heard_by_a.events(),
        vec![
            NodeEvent::TicketRedeemed { by: b.node.id() },
            NodeEvent::PeerJoined { id: b.node.id() },
        ]
    );
    // b knows the size of the vault before the first document is applied, and the count rises
    // to it when the fetch ends.
    let events = heard_by_b.events();
    assert_eq!(
        events[0],
        NodeEvent::FetchProgress {
            received: 0,
            total: Some(total),
        }
    );
    assert_eq!(
        events[1],
        NodeEvent::FetchProgress {
            received: total,
            total: Some(total),
        }
    );
    assert_eq!(events.len(), 2);
    // A later sync is not a first fetch and says nothing.
    b.node.sync_now().unwrap();
    assert_eq!(heard_by_b.events().len(), 2);
    assert_eq!(heard_by_a.events().len(), 2);
}

#[test]
fn a_rotation_is_told_peer_by_peer_before_its_report() {
    let a = Peer::new(Some(&fixture()), None);
    let b = Peer::new(None, None);
    let c = Peer::new(None, None);
    let d = Peer::new(None, None);
    a.node.sync_now().unwrap();
    for p in [&b, &c, &d] {
        p.node
            .accept_ticket(&a.node.ticket_with_addresses().unwrap().encode())
            .unwrap();
        p.node.sync_now().unwrap();
    }
    // d no longer knows a, so it turns the new key away.
    d.node.forget_peer(&a.node.id()).unwrap();
    let heard = Recorder::listening(&a.node);
    let report = a.node.rotate_key().unwrap();
    let events = heard.events();
    let (last, each) = events.split_last().unwrap();
    assert_eq!(last, &NodeEvent::RotationDone(report.clone()));
    let mut outcomes: Vec<(String, RotationOutcome)> = each
        .iter()
        .map(|event| match event {
            NodeEvent::KeyRotation { id, outcome } => (id.clone(), *outcome),
            other => panic!("not a rotation step: {other:?}"),
        })
        .collect();
    outcomes.sort_by(|x, y| x.0.cmp(&y.0));
    let mut expected = vec![
        (b.node.id(), RotationOutcome::Confirmed),
        (c.node.id(), RotationOutcome::Confirmed),
        (d.node.id(), RotationOutcome::Probed { holds_key: false }),
    ];
    expected.sort_by(|x, y| x.0.cmp(&y.0));
    assert_eq!(outcomes, expected);
    assert_eq!(report.reached, 2);
    assert_eq!(report.missed, vec![d.node.id()]);
}

#[test]
fn a_ticket_redeemed_twice_is_refused_the_second_time() {
    let a = Peer::new(Some(&fixture()), None);
    let b = Peer::new(None, None);
    let c = Peer::new(None, None);
    a.node.sync_now().unwrap();
    let ticket = a.node.ticket_with_addresses().unwrap().encode();
    b.node.accept_ticket(&ticket).unwrap();
    c.node.accept_ticket(&ticket).unwrap();
    b.node.sync_now().unwrap();
    assert!(c.node.sync_now().is_err());
    assert_eq!(c.read("Gift ideas.md"), None);
    let ids: Vec<String> = a.node.peers().unwrap().into_iter().map(|p| p.id).collect();
    assert_eq!(ids, vec![b.node.id()]);
    // Each ticket the maker issues is its own.
    let other = a.node.ticket_with_addresses().unwrap().encode();
    assert_ne!(other, ticket);
    c.node.forget_peer(&a.node.id()).unwrap();
    c.node.accept_ticket(&other).unwrap();
    c.node.sync_now().unwrap();
    assert_eq!(a.node.peers().unwrap().len(), 2);
}

#[test]
fn a_ticket_that_was_never_issued_pairs_nothing() {
    let a = Peer::new(Some(&fixture()), None);
    let b = Peer::new(None, None);
    let mut ticket = a.node.ticket_with_addresses().unwrap();
    ticket.id = [9; 16];
    b.node.accept_ticket(&ticket.encode()).unwrap();
    assert!(b.node.sync_now().is_err());
    assert!(a.node.peers().unwrap().is_empty());
}

#[test]
fn an_expired_ticket_is_refused_and_a_fresh_one_works() {
    let a = Peer::new(Some(&fixture()), None);
    let b = Peer::new(None, None);
    let c = Peer::new(None, None);
    a.node.sync_now().unwrap();
    a.node.set_ticket_lifetime(Duration::from_millis(500));
    let stale = a.node.ticket_with_addresses().unwrap().encode();
    std::thread::sleep(Duration::from_millis(900));
    b.node.accept_ticket(&stale).unwrap();
    assert!(
        b.node.sync_now().is_err(),
        "an expired ticket pairs nothing"
    );
    assert_eq!(b.read("Gift ideas.md"), None);
    assert!(a.node.peers().unwrap().is_empty());
    // A fresh ticket works, and making it drops the expired one from the table.
    a.node.set_ticket_lifetime(Duration::from_secs(60));
    let fresh = a.node.ticket_with_addresses().unwrap().encode();
    c.node.accept_ticket(&fresh).unwrap();
    c.node.sync_now().unwrap();
    assert_eq!(a.node.peers().unwrap().len(), 1);
}

#[test]
fn a_lost_acknowledgement_does_not_make_a_peer_missed() {
    let (a, b) = paired(None);
    b.node.sync_now().unwrap();
    b.node.drop_next_key_acks(1);
    let report = a.node.rotate_key().unwrap();
    assert_eq!(report.reached, 1);
    assert!(report.missed.is_empty());
    assert_eq!(b.node.ticket().unwrap().key, a.node.ticket().unwrap().key);
    assert!(!a.node.peers().unwrap()[0].missed);
    b.node.sync_now().unwrap();
}

#[test]
fn a_peer_that_kept_the_old_key_is_missed_and_marked() {
    let (a, b) = paired(None);
    b.node.sync_now().unwrap();
    let old = a.node.ticket().unwrap().key;
    // b no longer knows a, so it turns the new key away.
    b.node.forget_peer(&a.node.id()).unwrap();
    let report = a.node.rotate_key().unwrap();
    assert_eq!(report.reached, 0);
    assert_eq!(report.missed, vec![b.node.id()]);
    assert_eq!(b.node.ticket().unwrap().key, old);
    let peers = a.node.peers().unwrap();
    assert!(peers[0].missed);
}

/// A stranger that dials the node and says nothing it can open is dropped, and the node goes on.
#[test]
fn a_stranger_with_an_oversized_or_silent_frame_is_dropped() {
    use iroh::endpoint::presets;
    let (a, b) = paired(None);
    let ticket = a.node.ticket_with_addresses().unwrap();
    let runtime = tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .unwrap();
    runtime.block_on(async {
        let endpoint = iroh::Endpoint::builder(presets::Minimal)
            .relay_mode(iroh::RelayMode::Disabled)
            .bind()
            .await
            .unwrap();
        let mut addr = iroh::EndpointAddr::new(iroh::PublicKey::from_bytes(&ticket.node).unwrap());
        for ip in &ticket.addrs {
            addr = addr.with_ip_addr(*ip);
        }
        let connection = endpoint.connect(addr, b"bud/sync/1").await.unwrap();
        let (mut send, mut recv) = connection.open_bi().await.unwrap();
        send.write_all(&u32::MAX.to_be_bytes()).await.unwrap();
        let mut byte = [0u8; 1];
        let answer = tokio::time::timeout(Duration::from_secs(5), recv.read_exact(&mut byte)).await;
        assert!(
            matches!(answer, Ok(Err(_))),
            "the node closes on an oversized frame"
        );
        // A frame that is the right size but not sealed with the key is dropped too.
        let connection = endpoint
            .connect(
                iroh::EndpointAddr::new(iroh::PublicKey::from_bytes(&ticket.node).unwrap())
                    .with_ip_addr(ticket.addrs[0]),
                b"bud/sync/1",
            )
            .await
            .unwrap();
        let (mut send, mut recv) = connection.open_bi().await.unwrap();
        send.write_all(&64u32.to_be_bytes()).await.unwrap();
        send.write_all(&[7u8; 64]).await.unwrap();
        let answer = tokio::time::timeout(Duration::from_secs(5), recv.read_exact(&mut byte)).await;
        assert!(
            matches!(answer, Ok(Err(_))),
            "the node closes on a frame it cannot open"
        );
        endpoint.close().await;
    });
    // b is a real peer and a learns it by its proof; the stranger adds nothing to that.
    b.node.sync_now().unwrap();
    assert_eq!(
        a.node.peers().unwrap().len(),
        1,
        "the stranger was not remembered"
    );
}

#[test]
fn a_pair_sees_each_others_kind_and_name_after_the_first_session() {
    let a = Peer::new_as(Some(&fixture()), None, Identity::new("mac", "Study"));
    let b = Peer::new_as(None, None, Identity::new("tv", "Living room"));
    a.node.sync_now().unwrap();
    let ticket = a.node.ticket_with_addresses().unwrap().encode();
    let accepted = b.node.accept_ticket(&ticket).unwrap();
    assert_eq!(
        (accepted.kind, accepted.name),
        (None, None),
        "a ticket says nothing"
    );
    b.node.sync_now().unwrap();
    let seen_by_b = &b.node.peers().unwrap()[0];
    assert_eq!(seen_by_b.kind.as_deref(), Some("mac"));
    assert_eq!(seen_by_b.name.as_deref(), Some("Study"));
    assert_eq!(seen_by_b.label, None);
    let seen_by_a = &a.node.peers().unwrap()[0];
    assert_eq!(seen_by_a.kind.as_deref(), Some("tv"));
    assert_eq!(seen_by_a.name.as_deref(), Some("Living room"));
}

#[test]
fn a_label_sticks_and_survives_the_peers_own_name_changing() {
    let a = Peer::new_as(Some(&fixture()), None, Identity::new("mac", "Study"));
    let b = Peer::new_as(None, None, Identity::new("tv", "Living room"));
    a.node.sync_now().unwrap();
    let ticket = a.node.ticket_with_addresses().unwrap().encode();
    b.node.accept_ticket(&ticket).unwrap();
    b.node.sync_now().unwrap();
    let b_id = b.node.id();
    a.node
        .rename_peer(&b_id, Some("  The big screen "))
        .unwrap();
    assert_eq!(
        a.node.peers().unwrap()[0].label.as_deref(),
        Some("The big screen"),
        "trimmed"
    );
    let b = b.restart_as(Identity::new("tv", "Bedroom"));
    b.node.sync_now().unwrap();
    let seen = &a.node.peers().unwrap()[0];
    assert_eq!(
        seen.name.as_deref(),
        Some("Bedroom"),
        "the name follows the peer"
    );
    assert_eq!(
        seen.label.as_deref(),
        Some("The big screen"),
        "the label is this vault's"
    );
    a.node.rename_peer(&b_id, Some("")).unwrap();
    assert_eq!(
        a.node.peers().unwrap()[0].label,
        None,
        "an empty label takes it away"
    );
    assert!(a.node.rename_peer("not-a-peer", Some("x")).is_err());
    a.node.rename_peer(&b_id, Some("Screen")).unwrap();
    a.node.forget_peer(&b_id).unwrap();
    assert!(a.node.peers().unwrap().is_empty());
}

#[test]
fn a_node_that_says_nothing_about_itself_still_syncs() {
    let a = Peer::new_as(Some(&fixture()), None, Identity::new("mac", "Study"));
    let b = Peer::new(None, None);
    a.node.sync_now().unwrap();
    let ticket = a.node.ticket_with_addresses().unwrap().encode();
    b.node.accept_ticket(&ticket).unwrap();
    b.node.sync_now().unwrap();
    assert_eq!(b.read("Gift ideas.md"), a.read("Gift ideas.md"));
    let seen_by_a = &a.node.peers().unwrap()[0];
    assert_eq!(
        (seen_by_a.kind.as_deref(), seen_by_a.name.as_deref()),
        (None, None)
    );
    let seen_by_b = &b.node.peers().unwrap()[0];
    assert_eq!(seen_by_b.kind.as_deref(), Some("mac"));
}

#[test]
fn a_join_request_is_a_short_string_whose_four_words_both_sides_derive() {
    let t = Peer::new(None, None);
    let request = t.node.join_request().unwrap();
    let text = request.encode();
    assert!(text.starts_with("budr1"), "{text}");
    assert!(text.chars().all(|c| c.is_ascii_alphanumeric()));
    assert_eq!(JoinRequest::parse(&text).unwrap(), request);
    assert_eq!(JoinRequest::parse(&text.to_uppercase()).unwrap(), request);
    let words = request.words();
    assert_eq!(JoinRequest::parse(&text).unwrap().words(), words);
    assert!(words
        .iter()
        .all(|word| word.chars().all(|c| c.is_ascii_lowercase())));
    // The next request of the same node reads with other words.
    assert_ne!(t.node.join_request().unwrap().words(), words);
    assert!(
        JoinRequest::parse("bud1abc").is_err(),
        "a ticket is not a request"
    );
    assert!(JoinRequest::parse("budr1abc").is_err());
}

#[test]
fn the_phone_brings_the_key_to_a_tv_that_showed_a_request_and_the_tv_fetches_the_vault() {
    // a holds the vault, as the phone; t is a device without one, as the TV.
    let a = Peer::new(Some(&fixture()), None);
    let t = Peer::new(None, None);
    a.node.sync_now().unwrap();
    let heard_by_a = Recorder::listening(&a.node);
    let heard_by_t = Recorder::listening(&t.node);
    let shown = t.node.join_request().unwrap();
    let read = a.node.read_request(&shown.encode()).unwrap();
    assert_eq!(read.words(), shown.words(), "the same four words on both");
    assert!(
        t.node.peers().unwrap().is_empty(),
        "nothing moves before the confirmation"
    );
    assert!(a.node.peers().unwrap().is_empty());
    let peer = a.node.confirm_request(&read).unwrap();
    assert_eq!(peer.id, t.node.id());
    assert_eq!(
        heard_by_t.events(),
        vec![NodeEvent::PeerJoined { id: a.node.id() }]
    );
    assert_eq!(
        heard_by_a.events(),
        vec![NodeEvent::PeerJoined { id: t.node.id() }]
    );
    // The TV holds the vault key now and syncs as any peer does; its first sync is a first
    // fetch, told with the size of the vault.
    assert_eq!(t.node.ticket().unwrap().key, a.node.ticket().unwrap().key);
    assert_eq!(t.node.peers().unwrap()[0].id, a.node.id());
    t.node.sync_now().unwrap();
    assert!(t.read("Gift ideas.md").is_some(), "the vault came over");
    let total = a.vault.lock().unwrap().bud_count().unwrap();
    assert_eq!(
        heard_by_t.events()[1..],
        [
            NodeEvent::FetchProgress {
                received: 0,
                total: Some(total),
            },
            NodeEvent::FetchProgress {
                received: total,
                total: Some(total),
            },
        ]
    );
    t.node.sync_now().unwrap();
    assert_eq!(
        heard_by_t.events().len(),
        3,
        "a later sync is not a first fetch"
    );
    let edited = format!("{}Candles.\n", a.read("Gift ideas.md").unwrap());
    a.write("Gift ideas.md", &edited);
    a.node.sync_now().unwrap();
    eventually("the edit reaches the tv", || {
        t.read("Gift ideas.md") == Some(edited.clone())
    });
}

#[test]
fn a_join_request_is_refused_after_its_lifetime_on_either_side() {
    let a = Peer::new(Some(&fixture()), None);
    let t = Peer::new(None, None);
    t.node.set_ticket_lifetime(Duration::from_millis(1));
    let shown = t.node.join_request().unwrap();
    std::thread::sleep(Duration::from_millis(10));
    // The phone, with the usual lifetime, still reads the words; the TV turns the key away.
    let read = a.node.read_request(&shown.encode()).unwrap();
    assert!(a.node.confirm_request(&read).is_err());
    assert!(t.node.peers().unwrap().is_empty());
    assert!(a.node.peers().unwrap().is_empty());
    // A phone with the short lifetime refuses to read it at all.
    a.node.set_ticket_lifetime(Duration::from_millis(1));
    assert!(a.node.read_request(&shown.encode()).is_err());
}

#[test]
fn a_key_under_the_wrong_secret_is_turned_away_and_a_request_is_good_once() {
    let a = Peer::new(Some(&fixture()), None);
    let t = Peer::new(None, None);
    let shown = t.node.join_request().unwrap();
    // A code with the TV's address but not its secret shows other words, and brings nothing.
    let forged = JoinRequest {
        secret: [9; 32],
        ..shown.clone()
    };
    assert_ne!(forged.words(), shown.words());
    assert!(a.node.confirm_request(&forged).is_err());
    assert!(t.node.peers().unwrap().is_empty());
    // The right one works, once.
    a.node.confirm_request(&shown).unwrap();
    let b = Peer::new(Some(&fixture()), None);
    assert!(
        b.node.confirm_request(&shown).is_err(),
        "the request was used"
    );
    assert_eq!(t.node.peers().unwrap().len(), 1);
    // A TV that is paired already keeps its key, whatever request it shows.
    let again = t.node.join_request().unwrap();
    assert!(b.node.confirm_request(&again).is_err());
    assert_eq!(t.node.peers().unwrap().len(), 1);
    assert_eq!(t.node.ticket().unwrap().key, a.node.ticket().unwrap().key);
    // A vault does not read its own request.
    assert!(t.node.read_request(&again.encode()).is_err());
}
