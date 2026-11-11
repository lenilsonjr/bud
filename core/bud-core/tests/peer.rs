//! The peer transport: two vaults in one process pair with a ticket and exchange documents over
//! the loopback interface, with the relay off.

mod common;

use bud_core::{
    Identity, JoinRequest, Node, NodeEvent, NodeListener, NodeOptions, PeerInfo, Relay,
    RotationOutcome, Ticket, Vault,
};
use common::{copy_dir, fingerprint, fixture};
use pretty_assertions::assert_eq;
use std::net::{IpAddr, Ipv4Addr, Ipv6Addr, SocketAddr};
use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant, SystemTime};

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
        Peer::start(seed, interval, identity, None)
    }

    /// A node on a fresh folder and index, seeded from `seed`, and back on the pairing `kept`
    /// before it starts when there is one.
    fn start(
        seed: Option<&Path>,
        interval: Option<Duration>,
        identity: Identity,
        kept: Option<(&[u8], SystemTime)>,
    ) -> Peer {
        let dir = tempfile::tempdir().unwrap();
        if let Some(seed) = seed {
            copy_dir(seed, dir.path());
        }
        let index = tempfile::tempdir().unwrap();
        let vault = Vault::open(dir.path(), index.path().join("index.db")).unwrap();
        if let Some((kept, at)) = kept {
            assert!(vault.restore_pairing_at(kept, at).unwrap());
        }
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

/// The phone `a` confirms `shown` while the person at the TV `t` answers the key on offer with
/// `keep`, as both happen at once in use. What the TV was told of the offer comes back too.
fn confirm_with_tv(
    a: &Peer,
    t: &Peer,
    shown: &JoinRequest,
    keep: bool,
) -> (bud_core::Result<PeerInfo>, Vec<NodeEvent>) {
    let heard = Recorder::listening(&t.node);
    std::thread::scope(|scope| {
        let confirming = scope.spawn(|| a.node.confirm_request(shown));
        eventually("the tv is told of the key", || {
            heard
                .events()
                .iter()
                .any(|event| matches!(event, NodeEvent::JoinOffered { .. }))
        });
        t.node.answer_join(keep).unwrap();
        (confirming.join().unwrap(), heard.events())
    })
}

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

/// A device whose folder and index were cleared, back on the pairing it kept, its node running.
fn restored(kept: &[u8]) -> Peer {
    restored_at(kept, SystemTime::now())
}

/// The same, with the pairing brought back as if at `at`.
fn restored_at(kept: &[u8], at: SystemTime) -> Peer {
    Peer::start(None, None, Identity::default(), Some((kept, at)))
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
fn the_side_that_takes_an_edit_hears_the_sync_finish() {
    let (a, b) = paired(None);
    b.node.sync_now().unwrap();
    let heard_by_a = Recorder::listening(&a.node);
    let heard_by_b = Recorder::listening(&b.node);
    let finished = |heard: &Recorder| {
        heard
            .events()
            .into_iter()
            .filter_map(|event| match event {
                NodeEvent::SyncFinished(report) => Some(report),
                _ => None,
            })
            .collect::<Vec<_>>()
    };
    // Nothing to take, nothing told.
    b.node.sync_now().unwrap();
    assert_eq!(heard_by_a.events(), vec![]);
    assert_eq!(heard_by_b.events(), vec![]);

    // b takes a's edit in the answer to its own dial.
    let name = "Gift ideas.md";
    let edited = format!("{}A scarf.\n", a.read(name).unwrap());
    a.write(name, &edited);
    b.node.sync_now().unwrap();
    assert_eq!(b.read(name), Some(edited));
    let told = finished(&heard_by_b);
    assert_eq!(told.len(), 1);
    assert!(told[0].changed() && told[0].written > 0, "{told:?}");
    assert_eq!(finished(&heard_by_a), vec![]);

    // a takes b's edit in a session it answers.
    let edited = format!("{}And gloves.\n", b.read(name).unwrap());
    b.write(name, &edited);
    b.node.sync_now().unwrap();
    eventually("a hears the sync finish", || {
        finished(&heard_by_a).len() == 1
    });
    assert_eq!(a.read(name), Some(edited));
    assert!(finished(&heard_by_a)[0].written > 0);
    assert_eq!(finished(&heard_by_b).len(), 1);
}

#[test]
fn a_session_lost_after_its_changes_are_applied_still_tells_the_sync_finish() {
    let (a, b) = paired(None);
    b.node.sync_now().unwrap();
    let heard_by_a = Recorder::listening(&a.node);
    let name = "Gift ideas.md";
    let edited = format!("{}A scarf.\n", b.read(name).unwrap());
    b.write(name, &edited);
    // a takes b's edit and ends the session without confirming it, so b's sync fails.
    a.node.drop_next_dones(1);
    assert!(b.node.sync_now().is_err());
    eventually("a hears the sync finish", || {
        heard_by_a
            .events()
            .iter()
            .any(|event| matches!(event, NodeEvent::SyncFinished(report) if report.changed()))
    });
    assert_eq!(a.read(name), Some(edited));
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
    b.node.accept_ticket(&ticket).unwrap();
    // The maker still refuses a node it removed; only the maker can lift that.
    assert!(b.node.sync_now().is_err());
    a.node.allow_peer(&b.node.id()).unwrap();
    b.node.sync_now().unwrap();
    assert_eq!(a.node.peers().unwrap().len(), 1);
}

#[test]
fn a_new_ticket_of_the_vault_that_removed_this_one_waits_until_it_is_let_back_in() {
    let (a, b) = paired(None);
    b.node.sync_now().unwrap();
    a.node.forget_peer(&b.node.id()).unwrap();
    assert!(b.node.sync_now().is_err());
    assert!(b.node.peers().unwrap().is_empty(), "b let a go");
    let ticket = a.node.ticket_with_addresses().unwrap().encode();
    b.node.accept_ticket(&ticket).unwrap();
    let heard = Recorder::listening(&b.node);
    // a still refuses b and says it removed it, but b holds a ticket of a's it has not
    // redeemed: a stays, and so does the ticket.
    assert!(b.node.sync_now().is_err());
    let ids: Vec<String> = b.node.peers().unwrap().into_iter().map(|p| p.id).collect();
    assert_eq!(ids, vec![a.node.id()]);
    assert!(heard.events().is_empty());
    a.node.allow_peer(&b.node.id()).unwrap();
    b.node.sync_now().unwrap();
    assert_eq!(a.node.peers().unwrap().len(), 1);
    assert!(
        heard.events().contains(&NodeEvent::PairingChanged),
        "the ticket is spent"
    );
}

#[test]
fn a_rotation_lets_go_of_a_peer_that_removed_this_vault() {
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
    c.node.forget_peer(&a.node.id()).unwrap();
    let heard = Recorder::listening(&a.node);
    let report = a.node.rotate_key().unwrap();
    assert_eq!(report.reached, 1);
    assert!(report.missed.is_empty(), "let go, not missed");
    let ids: Vec<String> = a.node.peers().unwrap().into_iter().map(|p| p.id).collect();
    assert_eq!(ids, vec![b.node.id()]);
    assert!(heard
        .events()
        .contains(&NodeEvent::PeerRemoved { id: c.node.id() }));
}

#[test]
fn a_rotation_tells_a_removed_peer_apart_and_does_not_probe_it() {
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
    c.node.forget_peer(&a.node.id()).unwrap();
    let heard = Recorder::listening(&a.node);
    let before = a.node.dials();
    a.node.rotate_key().unwrap();
    // One dial each: c's hand over was refused as removed, so it is not probed.
    assert_eq!(a.node.dials() - before, 2);
    let steps: Vec<(String, RotationOutcome)> = heard
        .events()
        .iter()
        .filter_map(|event| match event {
            NodeEvent::KeyRotation { id, outcome } => Some((id.clone(), *outcome)),
            _ => None,
        })
        .collect();
    assert!(steps.contains(&(c.node.id(), RotationOutcome::Removed)));
    assert!(steps.contains(&(b.node.id(), RotationOutcome::Confirmed)));
}

#[test]
fn a_peer_that_removes_this_vault_during_the_probe_is_not_missed() {
    let (a, b) = paired(None);
    b.node.sync_now().unwrap();
    // b takes the new key without confirming it and removes a, so a hears it on the probe.
    b.node.drop_next_key_acks_and_remove(1);
    let heard = Recorder::listening(&a.node);
    let report = a.node.rotate_key().unwrap();
    assert_eq!(report.reached, 0);
    assert!(report.missed.is_empty(), "let go, not missed");
    assert!(a.node.peers().unwrap().is_empty());
    assert_eq!(
        heard.events(),
        vec![
            NodeEvent::PeerRemoved { id: b.node.id() },
            NodeEvent::KeyRotation {
                id: b.node.id(),
                outcome: RotationOutcome::Removed,
            },
            NodeEvent::RotationDone(report),
        ]
    );
}

#[test]
fn a_rotation_does_not_probe_a_removed_peer_kept_for_its_ticket_and_voids_the_ticket() {
    let (a, b) = paired(None);
    b.node.sync_now().unwrap();
    a.node.forget_peer(&b.node.id()).unwrap();
    assert!(b.node.sync_now().is_err());
    b.node
        .accept_ticket(&a.node.ticket_with_addresses().unwrap().encode())
        .unwrap();
    let heard = Recorder::listening(&b.node);
    let before = b.node.dials();
    let report = b.node.rotate_key().unwrap();
    assert_eq!(b.node.dials() - before, 1, "the hand over only");
    assert_eq!(report.reached, 0);
    assert!(report.missed.is_empty());
    // The ticket kept a through the hand over, but it came with the old key: once b takes the
    // new one, a goes, neither listed nor missed.
    assert_eq!(
        heard.events(),
        vec![
            NodeEvent::KeyRotation {
                id: a.node.id(),
                outcome: RotationOutcome::Removed,
            },
            NodeEvent::PeerRemoved { id: a.node.id() },
            NodeEvent::RotationDone(report),
        ]
    );
    assert!(b.node.peers().unwrap().is_empty());
}

/// The node ids this vault holds a ticket of and has not redeemed, read from its index.
fn pending_tickets(p: &Peer) -> Vec<String> {
    let conn = rusqlite::Connection::open(p.index.path().join("index.db")).unwrap();
    let mut statement = conn
        .prepare("SELECT node FROM peer_ticket ORDER BY node")
        .unwrap();
    statement
        .query_map([], |r| r.get(0))
        .unwrap()
        .map(Result::unwrap)
        .collect()
}

#[test]
fn a_key_handed_over_by_one_peer_keeps_the_ticket_of_another() {
    let c = Peer::new(Some(&fixture()), None);
    let a = Peer::new(None, None);
    let b = Peer::new(None, None);
    c.node.sync_now().unwrap();
    for p in [&a, &b] {
        p.node
            .accept_ticket(&c.node.ticket_with_addresses().unwrap().encode())
            .unwrap();
        p.node.sync_now().unwrap();
    }
    a.node
        .accept_ticket(&b.node.ticket_with_addresses().unwrap().encode())
        .unwrap();
    assert_eq!(pending_tickets(&a), vec![b.node.id()]);
    let report = c.node.rotate_key().unwrap();
    assert_eq!(report.reached, 2);
    assert_eq!(a.node.ticket().unwrap().key, c.node.ticket().unwrap().key);
    // Taking a key someone else made voids nothing this vault holds of its own.
    assert_eq!(pending_tickets(&a), vec![b.node.id()]);
    assert_eq!(a.node.peers().unwrap().len(), 2);
}

#[test]
fn an_expired_ticket_does_not_keep_a_peer_that_removed_this_vault() {
    let (a, b) = paired(None);
    b.node.sync_now().unwrap();
    a.node.forget_peer(&b.node.id()).unwrap();
    assert!(b.node.sync_now().is_err());
    b.node
        .accept_ticket(&a.node.ticket_with_addresses().unwrap().encode())
        .unwrap();
    b.node.set_ticket_lifetime(Duration::from_millis(500));
    std::thread::sleep(Duration::from_millis(1200));
    let heard = Recorder::listening(&b.node);
    assert!(b.node.sync_now().is_err());
    assert!(b.node.peers().unwrap().is_empty(), "the ticket expired");
    assert_eq!(
        heard.events(),
        vec![NodeEvent::PeerRemoved { id: a.node.id() }]
    );
}

#[test]
fn a_removed_peer_is_told_so_and_lets_the_vault_that_removed_it_go() {
    let (a, b) = paired(None);
    b.node.sync_now().unwrap();
    let heard = Recorder::listening(&b.node);
    a.node.forget_peer(&b.node.id()).unwrap();
    assert!(b.node.sync_now().is_err());
    assert!(b.node.peers().unwrap().is_empty(), "b let a go");
    assert_eq!(
        heard.events(),
        vec![NodeEvent::PeerRemoved { id: a.node.id() }]
    );
    // With no peer left there is no pairing to keep.
    assert_eq!(b.vault.lock().unwrap().pairing().unwrap(), None);
    // And b does not call again: the next round dials no one.
    b.node.sync_now().unwrap();
    assert_eq!(heard.events().len(), 1);
}

#[test]
fn a_peer_that_missed_a_rotation_is_turned_away_but_keeps_its_peer() {
    let (a, b) = paired(None);
    let stale = a.node.ticket_with_addresses().unwrap().encode();
    b.node.sync_now().unwrap();
    // b no longer knows a, without refusing it, so it turns the new key away and holds the
    // old one.
    b.node.forget_peer(&a.node.id()).unwrap();
    b.node.allow_peer(&a.node.id()).unwrap();
    let report = a.node.rotate_key().unwrap();
    assert_eq!(report.missed, vec![b.node.id()]);
    b.node.accept_ticket(&stale).unwrap();
    let heard = Recorder::listening(&b.node);
    assert!(b.node.sync_now().is_err(), "the old key is turned away");
    // Not told it was removed: a key it lacks is put right by pairing again, so a stays.
    let ids: Vec<String> = b.node.peers().unwrap().into_iter().map(|p| p.id).collect();
    assert_eq!(ids, vec![a.node.id()]);
    assert!(heard.events().is_empty());
    assert!(a.node.peers().unwrap()[0].missed);
}

#[test]
fn a_device_back_on_its_kept_pairing_lets_go_of_a_peer_that_removed_it() {
    let (a, b) = paired(None);
    b.node.sync_now().unwrap();
    let kept = b.vault.lock().unwrap().pairing().unwrap().unwrap();
    a.node.forget_peer(&b.node.id()).unwrap();
    // The cache is cleared and the device comes back as itself, with the peer it kept.
    drop(b);
    let c = restored(&kept);
    assert_eq!(c.node.peers().unwrap().len(), 1);
    let heard = Recorder::listening(&c.node);
    assert!(c.node.sync_now().is_err());
    assert!(c.node.peers().unwrap().is_empty());
    assert_eq!(
        heard.events(),
        vec![NodeEvent::PeerRemoved { id: a.node.id() }]
    );
    // Nothing is left to keep, so the copy kept elsewhere goes.
    assert_eq!(c.vault.lock().unwrap().pairing().unwrap(), None);
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
    let heard_by_b = Recorder::listening(&b.node);
    let report = a.node.rotate_key().unwrap();
    assert_eq!(report.reached, 1);
    // b is told its pairing changed, so a copy of it kept elsewhere follows the new key.
    eventually("b hears its key changed", || {
        heard_by_b.events().contains(&NodeEvent::PairingChanged)
    });
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
    // Then the sync is over, with what it made.
    assert!(
        matches!(&events[2], NodeEvent::SyncFinished(report) if report.created > 0),
        "{events:?}"
    );
    // And the ticket b accepted is spent, which changes what b keeps of its pairing.
    assert_eq!(events[3], NodeEvent::PairingChanged);
    assert_eq!(events.len(), 4);
    // A later sync is not a first fetch and brings nothing, so it says nothing.
    b.node.sync_now().unwrap();
    assert_eq!(heard_by_b.events().len(), 4);
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
    // d no longer knows a, without refusing it, so it turns the new key away.
    d.node.forget_peer(&a.node.id()).unwrap();
    d.node.allow_peer(&a.node.id()).unwrap();
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
    // b no longer knows a, without refusing it, so it turns the new key away.
    b.node.forget_peer(&a.node.id()).unwrap();
    b.node.allow_peer(&a.node.id()).unwrap();
    let report = a.node.rotate_key().unwrap();
    assert_eq!(report.reached, 0);
    assert_eq!(report.missed, vec![b.node.id()]);
    assert_eq!(b.node.ticket().unwrap().key, old);
    let peers = a.node.peers().unwrap();
    assert!(peers[0].missed);
}

/// `a` holds the fixture vault; `b` and `c` each accepted a ticket of it and synced once.
fn paired_twice() -> (Peer, Peer, Peer) {
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
    (a, b, c)
}

#[test]
fn a_check_that_fails_during_a_rotation_still_lets_the_vault_take_the_confirmed_key() {
    let (a, b, c) = paired_twice();
    let old = a.node.ticket().unwrap().key;
    // c no longer knows a, without refusing it, so it turns the new key away and a checks it.
    c.node.forget_peer(&a.node.id()).unwrap();
    c.node.allow_peer(&a.node.id()).unwrap();
    a.node.fail_next_peer_checks(1);
    let heard = Recorder::listening(&a.node);
    let report = a.node.rotate_key().unwrap();
    assert_eq!(report.reached, 1);
    assert_eq!(report.missed, vec![c.node.id()], "unknown, so missed");
    let key = a.node.ticket().unwrap().key;
    assert_ne!(key, old);
    assert_eq!(b.node.ticket().unwrap().key, key);
    assert_eq!(
        heard.events().last(),
        Some(&NodeEvent::RotationDone(report))
    );
    b.node.sync_now().unwrap();
}

#[test]
fn a_peer_that_removed_this_vault_is_not_probed_when_letting_it_go_fails() {
    let (a, b, c) = paired_twice();
    c.node.forget_peer(&a.node.id()).unwrap();
    a.node.fail_next_drops(1);
    let heard = Recorder::listening(&a.node);
    let before = a.node.dials();
    let report = a.node.rotate_key().unwrap();
    assert_eq!(a.node.dials() - before, 2, "c heard as removed, not probed");
    assert_eq!(report.reached, 1);
    assert!(report.missed.is_empty());
    // The hand over could not let c go; the rotation does once the new key is in.
    let ids: Vec<String> = a.node.peers().unwrap().into_iter().map(|p| p.id).collect();
    assert_eq!(ids, vec![b.node.id()]);
    let events = heard.events();
    assert!(events.contains(&NodeEvent::PeerRemoved { id: c.node.id() }));
    assert_eq!(events.last(), Some(&NodeEvent::RotationDone(report)));
}

#[test]
fn a_clean_up_that_fails_after_the_new_key_is_in_does_not_fail_the_rotation() {
    let (a, b) = paired(None);
    b.node.sync_now().unwrap();
    a.node.forget_peer(&b.node.id()).unwrap();
    assert!(b.node.sync_now().is_err());
    b.node
        .accept_ticket(&a.node.ticket_with_addresses().unwrap().encode())
        .unwrap();
    let old = b.node.ticket().unwrap().key;
    // Letting a go fails on the hand over that hears the removal and once the new key is in.
    b.node.fail_next_drops(2);
    let heard = Recorder::listening(&b.node);
    let report = b.node.rotate_key().unwrap();
    assert_eq!(report.reached, 0);
    assert!(report.missed.is_empty());
    assert_eq!(
        heard.events(),
        vec![
            NodeEvent::KeyRotation {
                id: a.node.id(),
                outcome: RotationOutcome::Removed,
            },
            NodeEvent::RotationDone(report),
        ]
    );
    assert_ne!(b.node.ticket().unwrap().key, old, "the new key is in");
    // a stays listed until a later dial hears its removal again.
    assert_eq!(b.node.peers().unwrap().len(), 1);
}

/// A peer that takes the first message and drops its streams, leaving the connection open, so
/// the dialer hears no reason for the failure.
#[test]
fn a_dial_to_a_peer_that_drops_its_streams_stays_within_its_time() {
    use iroh::endpoint::presets;
    let a = Peer::new(Some(&fixture()), None);
    let runtime = tokio::runtime::Builder::new_multi_thread()
        .worker_threads(1)
        .enable_all()
        .build()
        .unwrap();
    let endpoint = runtime.block_on(async {
        iroh::Endpoint::builder(presets::Minimal)
            .relay_mode(iroh::RelayMode::Disabled)
            .alpns(vec![b"bud/sync/1".to_vec()])
            .bind()
            .await
            .unwrap()
    });
    let addrs = endpoint
        .bound_sockets()
        .into_iter()
        .map(|bound| match bound.ip() {
            IpAddr::V4(ip) if ip.is_unspecified() => {
                SocketAddr::new(IpAddr::V4(Ipv4Addr::LOCALHOST), bound.port())
            }
            IpAddr::V6(ip) if ip.is_unspecified() => {
                SocketAddr::new(IpAddr::V6(Ipv6Addr::LOCALHOST), bound.port())
            }
            _ => bound,
        })
        .collect();
    let serving = endpoint.clone();
    runtime.spawn(async move {
        while let Some(incoming) = serving.accept().await {
            let Ok(connection) = incoming.await else {
                continue;
            };
            tokio::spawn(async move {
                if let Ok((mut send, mut recv)) = connection.accept_bi().await {
                    let _ = recv.read(&mut [0u8; 64]).await;
                    let _ = send.reset(0u32.into());
                    let _ = recv.stop(0u32.into());
                }
                tokio::time::sleep(Duration::from_secs(30)).await;
                drop(connection);
            });
        }
    });
    let ticket = Ticket {
        node: *endpoint.id().as_bytes(),
        id: [7; 16],
        relay: Relay::Off,
        key: a.node.ticket().unwrap().key,
        addrs,
    };
    a.node.accept_ticket(&ticket.encode()).unwrap();
    // Shorter than the wait for a close, which once came on top of a dial's time.
    a.node.set_dial_timeout(Duration::from_millis(800));
    let start = Instant::now();
    assert!(a.node.sync_now().is_err());
    let took = start.elapsed();
    assert!(took < Duration::from_millis(1500), "the dial took {took:?}");
    runtime.block_on(endpoint.close());
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
fn a_join_request_is_a_short_string_whose_six_words_both_sides_derive() {
    let t = Peer::new(None, None);
    let request = t.node.join_request().unwrap();
    let text = request.encode();
    assert!(text.starts_with("budr1"), "{text}");
    assert!(text.chars().all(|c| c.is_ascii_alphanumeric()));
    assert_eq!(JoinRequest::parse(&text).unwrap(), request);
    assert_eq!(JoinRequest::parse(&text.to_uppercase()).unwrap(), request);
    let words = request.words();
    assert_eq!(JoinRequest::parse(&text).unwrap().words(), words);
    let mut distinct = words.to_vec();
    distinct.sort();
    distinct.dedup();
    assert_eq!(distinct.len(), 6, "no word repeats: {words:?}");
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
    assert_eq!(read.words(), shown.words(), "the same six words on both");
    assert!(
        t.node.peers().unwrap().is_empty(),
        "nothing moves before the confirmation"
    );
    assert!(a.node.peers().unwrap().is_empty());
    assert!(
        t.node.answer_join(true).is_err(),
        "nothing is on offer before the phone calls"
    );
    let (peer, told) = confirm_with_tv(&a, &t, &read, true);
    let peer = peer.unwrap();
    assert_eq!(peer.id, t.node.id());
    // The TV was told who brought the key and the words of its own request, and kept the key
    // only once answered.
    let offered = NodeEvent::JoinOffered {
        id: a.node.id(),
        kind: None,
        name: None,
        words: shown.words().to_vec(),
    };
    assert_eq!(
        told,
        vec![offered.clone(), NodeEvent::PeerJoined { id: a.node.id() }]
    );
    assert_eq!(
        heard_by_t.events(),
        vec![offered, NodeEvent::PeerJoined { id: a.node.id() }]
    );
    assert_eq!(
        heard_by_a.events(),
        vec![NodeEvent::PeerJoined { id: t.node.id() }]
    );
    // The TV holds the vault key now and syncs as any peer does; its first sync is a first
    // fetch, told with the size of the vault, then what it made.
    assert_eq!(t.node.ticket().unwrap().key, a.node.ticket().unwrap().key);
    assert_eq!(t.node.peers().unwrap()[0].id, a.node.id());
    t.node.sync_now().unwrap();
    assert!(t.read("Gift ideas.md").is_some(), "the vault came over");
    let total = a.vault.lock().unwrap().bud_count().unwrap();
    assert_eq!(
        heard_by_t.events()[2..4],
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
    assert!(
        matches!(&heard_by_t.events()[4], NodeEvent::SyncFinished(report) if report.created > 0)
    );
    t.node.sync_now().unwrap();
    assert_eq!(
        heard_by_t.events().len(),
        5,
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
    // The right one works, once: a second device of the same vault, which the TV would take a
    // key from, is turned away by the used request alone.
    confirm_with_tv(&a, &t, &shown, true).0.unwrap();
    let c = Peer::new(None, None);
    c.node
        .accept_ticket(&a.node.ticket_with_addresses().unwrap().encode())
        .unwrap();
    c.node.sync_now().unwrap();
    assert_eq!(c.node.ticket().unwrap().key, a.node.ticket().unwrap().key);
    // Turned away at once: nothing is put to the person at the TV, and it is not a refusal.
    let heard = Recorder::listening(&t.node);
    let started = Instant::now();
    let used = c.node.confirm_request(&shown).unwrap_err().to_string();
    assert!(started.elapsed() < Duration::from_secs(20), "{used}");
    assert!(!used.contains("refused"), "{used}");
    assert!(
        !heard
            .events()
            .iter()
            .any(|event| matches!(event, NodeEvent::JoinOffered { .. })),
        "the used request offered nothing"
    );
    assert_eq!(t.node.peers().unwrap().len(), 1);
    // A TV that is paired already keeps its key, whatever request it shows, and puts nothing to
    // the person.
    let b = Peer::new(Some(&fixture()), None);
    let again = t.node.join_request().unwrap();
    let started = Instant::now();
    assert!(b.node.confirm_request(&again).is_err());
    assert!(started.elapsed() < Duration::from_secs(20));
    assert!(!heard
        .events()
        .iter()
        .any(|event| matches!(event, NodeEvent::JoinOffered { .. })));
    assert_eq!(t.node.peers().unwrap().len(), 1);
    assert_eq!(t.node.ticket().unwrap().key, a.node.ticket().unwrap().key);
    // A vault does not read its own request.
    assert!(t.node.read_request(&again.encode()).is_err());
}

#[test]
fn a_key_the_person_at_the_tv_refuses_does_not_stay_and_the_request_is_still_on_show() {
    let a = Peer::new(Some(&fixture()), None);
    let t = Peer::new(None, None);
    let shown = t.node.join_request().unwrap();
    let (refused, told) = confirm_with_tv(&a, &t, &shown, false);
    let err = refused.unwrap_err().to_string();
    assert!(err.contains("refused"), "{err}");
    assert!(t.node.peers().unwrap().is_empty());
    assert!(a.node.peers().unwrap().is_empty());
    assert_ne!(t.node.ticket().unwrap().key, a.node.ticket().unwrap().key);
    assert_eq!(told.len(), 1, "told of the offer and nothing more");
    assert!(t.node.answer_join(true).is_err(), "the offer is over");
    // The same code still works: the person can try again after a refusal.
    confirm_with_tv(&a, &t, &shown, true).0.unwrap();
    assert_eq!(t.node.peers().unwrap().len(), 1);
    assert_eq!(t.node.ticket().unwrap().key, a.node.ticket().unwrap().key);
}

#[test]
fn a_malformed_request_is_refused_and_an_edited_one_shows_other_words() {
    let a = Peer::new(Some(&fixture()), None);
    let t = Peer::new(None, None);
    let shown = t.node.join_request().unwrap();
    // A time no clock made, far past or far ahead, is refused rather than overflowing.
    for issued in [i64::MIN, i64::MAX, shown.issued + 24 * 3600 * 1000] {
        let odd = JoinRequest {
            issued,
            ..shown.clone()
        };
        assert!(a.node.read_request(&odd.encode()).is_err(), "{issued}");
    }
    let bad_relay = JoinRequest {
        relay: Relay::Custom("not a url".to_string()),
        ..shown.clone()
    };
    assert!(a.node.read_request(&bad_relay.encode()).is_err());
    // The words cover the whole code: an edited address or relay reads with other words, so the
    // person sees the mismatch.
    let moved = JoinRequest {
        addrs: vec!["127.0.0.1:1".parse().unwrap()],
        ..shown.clone()
    };
    assert_ne!(moved.words(), shown.words());
    let elsewhere = JoinRequest {
        relay: Relay::Default,
        ..shown.clone()
    };
    assert_ne!(elsewhere.words(), shown.words());
    // What is written of a request keeps its secret out.
    let written = format!("{shown:?}");
    assert!(!written.contains("secret"), "{written}");
    assert!(written.contains(&shown.id()));
}

#[test]
fn a_vault_with_no_peer_keeps_no_pairing() {
    let a = Peer::new(Some(&fixture()), None);
    assert_eq!(a.vault.lock().unwrap().pairing().unwrap(), None);
}

#[test]
fn a_device_that_lost_its_folder_and_index_comes_back_with_its_kept_pairing() {
    let (a, b) = paired(None);
    b.node.sync_now().unwrap();
    b.node.rename_peer(&a.node.id(), Some("Studio")).unwrap();
    let kept = b.vault.lock().unwrap().pairing().unwrap().unwrap();
    let id = b.node.id();
    // The cache is cleared: the folder and the index go, the node with them.
    drop(b);

    let dir = tempfile::tempdir().unwrap();
    let index = tempfile::tempdir().unwrap();
    let vault = Vault::open(dir.path(), index.path().join("index.db")).unwrap();
    assert!(vault.restore_pairing(&kept).unwrap());
    let vault = Arc::new(Mutex::new(vault));
    let node = Node::start_with(
        Arc::clone(&vault),
        NodeOptions {
            relay: Relay::Off,
            interval: None,
            identity: Identity::default(),
        },
    )
    .unwrap();
    let c = Peer {
        vault,
        dir,
        index,
        node,
    };
    assert_eq!(c.node.id(), id, "the same device, by its node key");
    let peers = c.node.peers().unwrap();
    assert_eq!(peers.len(), 1);
    assert_eq!(peers[0].id, a.node.id());
    assert_eq!(peers[0].label.as_deref(), Some("Studio"));

    // The first session fetches the whole vault, and says so.
    let heard = Recorder::listening(&c.node);
    c.node.sync_now().unwrap();
    let total = a.vault.lock().unwrap().bud_count().unwrap();
    assert_eq!(
        heard.events()[..2],
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
    for name in [
        "Gift ideas.md",
        "Launch the newsletter.md",
        "Launch the newsletter/Pick a name/Shortlist three candidates.md",
        "Routines/Weekly review.md",
    ] {
        assert_eq!(c.read(name), a.read(name), "{name}");
    }

    // And it is a peer like before: an edit made on it reaches the other.
    let name = "Gift ideas.md";
    let edited = format!("{}Candles.\n", c.read(name).unwrap());
    c.write(name, &edited);
    c.node.sync_now().unwrap();
    eventually("the edit reaches a", || {
        a.read(name) == Some(edited.clone())
    });
}

#[test]
fn the_same_pairing_encodes_the_same_whatever_the_order_of_its_rows() {
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
    a.node.rename_peer(&b.node.id(), Some("Den")).unwrap();
    a.node.rename_peer(&c.node.id(), Some("Studio")).unwrap();
    let first = a.vault.lock().unwrap().pairing().unwrap().unwrap();
    // The same label again, its row now after the other.
    a.node.rename_peer(&b.node.id(), None).unwrap();
    a.node.rename_peer(&b.node.id(), Some("Den")).unwrap();
    let second = a.vault.lock().unwrap().pairing().unwrap().unwrap();
    assert_eq!(first, second);
}

#[test]
fn a_copy_taken_before_the_first_session_still_redeems_its_ticket() {
    let (a, b) = paired(None);
    let kept = b.vault.lock().unwrap().pairing().unwrap().unwrap();
    let id = b.node.id();
    // The cache is cleared before b ever reached a.
    drop(b);
    let c = restored(&kept);
    c.node.sync_now().unwrap();
    assert_eq!(
        a.node.peers().unwrap()[0].id,
        id,
        "a let it in on the ticket"
    );
}

#[test]
fn a_ticket_spent_by_the_first_session_does_not_come_back_with_an_older_copy() {
    let (a, b) = paired(None);
    // Taken while the ticket was still to redeem; the first session spends it after.
    let kept = b.vault.lock().unwrap().pairing().unwrap().unwrap();
    b.node.sync_now().unwrap();
    a.node.forget_peer(&b.node.id()).unwrap();
    drop(b);
    // Brought back once the ticket could no longer be redeemed anyway.
    let later = SystemTime::now() + Duration::from_secs(11 * 60);
    let c = restored_at(&kept, later);
    let heard = Recorder::listening(&c.node);
    // With no ticket held for a, the device lets go of the peer that removed it, rather than
    // waiting for a ticket that will never redeem.
    assert!(c.node.sync_now().is_err());
    assert!(c.node.peers().unwrap().is_empty());
    assert_eq!(
        heard.events(),
        vec![NodeEvent::PeerRemoved { id: a.node.id() }]
    );
}

#[test]
fn a_kept_pairing_never_replaces_a_live_one() {
    let (_a, b) = paired(None);
    let kept = b.vault.lock().unwrap().pairing().unwrap().unwrap();
    // b has its peers and its key: the copy changes nothing.
    assert!(!b.vault.lock().unwrap().restore_pairing(&kept).unwrap());
    // A fresh index on which a node already made its key refuses it too.
    let other = Peer::new(None, None);
    assert!(!other.vault.lock().unwrap().restore_pairing(&kept).unwrap());
    assert!(other.node.peers().unwrap().is_empty());
}

#[test]
fn a_damaged_pairing_is_refused_and_leaves_the_index_bare() {
    let (_a, b) = paired(None);
    let mut kept = b.vault.lock().unwrap().pairing().unwrap().unwrap();
    kept.truncate(kept.len() / 2);
    let dir = tempfile::tempdir().unwrap();
    let index = tempfile::tempdir().unwrap();
    let vault = Vault::open(dir.path(), index.path().join("index.db")).unwrap();
    assert!(vault.restore_pairing(&kept).is_err());
    assert!(vault.restore_pairing(b"").is_err());
    assert!(!index.path().join("node.key").exists());
}

#[test]
fn a_restore_cut_short_after_its_rows_is_taken_again() {
    let (a, b) = paired(None);
    b.node.sync_now().unwrap();
    let kept = b.vault.lock().unwrap().pairing().unwrap().unwrap();
    drop(b);
    let dir = tempfile::tempdir().unwrap();
    let index = tempfile::tempdir().unwrap();
    let vault = Vault::open(dir.path(), index.path().join("index.db")).unwrap();
    assert!(vault.takes_pairing(&kept).unwrap());
    assert!(vault.restore_pairing(&kept).unwrap());
    // The key goes, as if the restore stopped between the rows and the key.
    std::fs::remove_file(index.path().join("node.key")).unwrap();
    assert!(
        vault.takes_pairing(&kept).unwrap(),
        "rows of the kept pairing alone"
    );
    assert!(vault.restore_pairing(&kept).unwrap());
    assert!(index.path().join("node.key").is_file());
    assert!(!index.path().join("node.key.new").exists());
    // Whole now: nothing more to take.
    assert!(!vault.takes_pairing(&kept).unwrap());
    assert!(!vault.restore_pairing(&kept).unwrap());
    let node = Node::start_with(
        Arc::new(Mutex::new(vault)),
        NodeOptions {
            relay: Relay::Off,
            interval: None,
            identity: Identity::default(),
        },
    )
    .unwrap();
    assert_eq!(node.peers().unwrap()[0].id, a.node.id());
}

#[test]
fn a_node_key_with_no_peers_never_takes_a_kept_pairing() {
    let (a, b) = paired(None);
    b.node.sync_now().unwrap();
    let kept = b.vault.lock().unwrap().pairing().unwrap().unwrap();
    assert!(Vault::pairing_is_usable(&kept));
    assert!(!Vault::pairing_is_usable(&kept[..kept.len() / 2]));
    // The person removed the last peer: the same key, no peers. That pairing stays gone.
    b.node.forget_peer(&a.node.id()).unwrap();
    assert!(b.node.peers().unwrap().is_empty());
    let vault = b.vault.lock().unwrap();
    assert!(!vault.takes_pairing(&kept).unwrap());
    assert!(!vault.restore_pairing(&kept).unwrap());
    drop(vault);
    assert!(b.node.peers().unwrap().is_empty());

    // Another key with no peers: that device is someone else.
    let dir = tempfile::tempdir().unwrap();
    let index = tempfile::tempdir().unwrap();
    std::fs::write(index.path().join("node.key"), [9u8; 32]).unwrap();
    let vault = Vault::open(dir.path(), index.path().join("index.db")).unwrap();
    assert!(!vault.takes_pairing(&kept).unwrap());
    assert!(!vault.restore_pairing(&kept).unwrap());
}
