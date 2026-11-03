//! The peer surface, called the way Swift calls it: two vaults in one process pair with a ticket
//! and sync over the loopback interface, with the relay off.

use bud_ffi::{
    open_vault, start_node, start_node_as, PeerEvent, PeerListener, PeerNode, RelaySetting, Vault,
    VaultError,
};
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

struct Side {
    vault: Arc<Vault>,
    node: Arc<PeerNode>,
    dir: tempfile::TempDir,
    _index: tempfile::TempDir,
}

fn side(files: &[(&str, &str)], relay: RelaySetting) -> Side {
    let dir = tempfile::tempdir().unwrap();
    for (name, text) in files {
        let path = dir.path().join(name);
        std::fs::create_dir_all(path.parent().unwrap()).unwrap();
        std::fs::write(path, text).unwrap();
    }
    let index = tempfile::tempdir().unwrap();
    let vault = open_vault(
        dir.path().to_str().unwrap().to_string(),
        index.path().join("index.db").to_str().unwrap().to_string(),
    )
    .unwrap();
    let node = start_node(Arc::clone(&vault), relay).unwrap();
    Side {
        vault,
        node,
        dir,
        _index: index,
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

/// `a` holds two notes, `b` is empty and has accepted a's ticket.
fn paired() -> (Side, Side) {
    let a = side(
        &[
            ("Newsletter.md", "A note about the newsletter.\n"),
            ("Newsletter/Pick a name.md", "Short names read better.\n"),
        ],
        RelaySetting::Off,
    );
    let b = side(&[], RelaySetting::Off);
    a.node.sync_now().unwrap();
    b.node.accept_ticket(a.node.ticket(true).unwrap()).unwrap();
    (a, b)
}

#[test]
fn a_ticket_is_a_string_and_the_same_ticket_as_qr_rows() {
    let a = side(&[("Newsletter.md", "Hello.\n")], RelaySetting::Off);
    let ticket = a.node.ticket(false).unwrap();
    assert!(ticket.starts_with("bud1"));
    assert_ne!(
        a.node.ticket(true).unwrap(),
        ticket,
        "with addresses is longer"
    );
    let rows = a.node.ticket_qr(false).unwrap();
    assert!(rows.len() >= 21);
    assert!(rows.iter().all(|row| row.len() == rows.len()), "a square");
    assert!(rows.iter().flatten().any(|dark| *dark));
    assert!(rows.iter().flatten().any(|dark| !*dark));
    assert!(!a.node.id().unwrap().is_empty());
}

#[test]
fn a_node_starts_with_each_relay_setting() {
    let url = RelaySetting::Custom {
        url: "https://relay.example.org/".to_string(),
    };
    let custom = side(&[], url.clone());
    let peer = side(&[], RelaySetting::Off);
    let accepted = peer
        .node
        .accept_ticket(custom.node.ticket(false).unwrap())
        .unwrap();
    assert_eq!(accepted.relay, url);
    assert_eq!(accepted.last_seen, None);
    let default = side(&[], RelaySetting::Default);
    default.node.stop();
    let bad = open_vault_and_start("not a url");
    assert!(matches!(bad, Err(VaultError::Invalid { .. })));
}

fn open_vault_and_start(url: &str) -> Result<Arc<PeerNode>, VaultError> {
    let dir = tempfile::tempdir().unwrap();
    let index = tempfile::tempdir().unwrap();
    let vault = open_vault(
        dir.path().to_str().unwrap().to_string(),
        index.path().join("index.db").to_str().unwrap().to_string(),
    )?;
    start_node(vault, RelaySetting::Custom { url: url.into() })
}

#[test]
fn accepting_a_ticket_lists_the_peer_and_sync_now_moves_the_notes() {
    let (a, b) = paired();
    let peers = b.node.peers().unwrap();
    assert_eq!(peers.len(), 1);
    assert_eq!(peers[0].id, a.node.id().unwrap());
    assert_eq!(peers[0].relay, RelaySetting::Off);
    assert_eq!(peers[0].last_seen, None, "not yet synced");

    let summary = b.node.sync_now().unwrap();
    assert!(summary.created > 0 || summary.written > 0 || summary.ops > 0);
    assert_eq!(
        std::fs::read_to_string(b.dir.path().join("Newsletter/Pick a name.md")).unwrap(),
        "Short names read better.\n"
    );
    assert!(b
        .vault
        .bud("Newsletter/Pick a name.md".into())
        .unwrap()
        .is_some());

    let seen = b.node.peers().unwrap()[0].last_seen.unwrap();
    assert!(seen > 1_700_000_000);
    eventually("the answering side learns its peer", || {
        a.node.peers().unwrap().len() == 1
    });
}

#[test]
fn the_state_counts_connected_peers_and_pending_changes() {
    let (a, b) = paired();
    let fresh = b.node.state().unwrap();
    assert!(fresh.idle);
    assert_eq!(fresh.connected_peers, 0);

    b.node.sync_now().unwrap();
    let synced = b.node.state().unwrap();
    assert!(synced.idle);
    assert_eq!(synced.connected_peers, 1);
    assert_eq!(synced.pending_changes, 0);

    std::fs::write(b.dir.path().join("Newsletter/Outside.md"), "Hello.\n").unwrap();
    assert_eq!(b.node.state().unwrap().pending_changes, 1);
    b.node.sync_now().unwrap();
    assert_eq!(b.node.state().unwrap().pending_changes, 0);
    eventually("the edit reaches the other vault", || {
        a.node.sync_now().unwrap();
        a.dir.path().join("Newsletter/Outside.md").exists()
    });
}

#[test]
fn forgetting_a_peer_removes_it_and_an_unknown_one_is_an_error() {
    let (a, b) = paired();
    b.node.sync_now().unwrap();
    let id = a.node.id().unwrap();
    b.node.forget_peer(id.clone()).unwrap();
    assert!(b.node.peers().unwrap().is_empty());
    assert_eq!(b.node.state().unwrap().connected_peers, 0);
    let again = b.node.forget_peer(id);
    match again {
        Err(VaultError::Invalid { message }) => assert!(message.contains("no peer")),
        other => panic!("expected an error, got {other:?}"),
    }
}

#[test]
fn errors_keep_the_core_message() {
    let (a, b) = paired();
    let bad = b.node.accept_ticket("not a ticket".into());
    match bad {
        Err(VaultError::Invalid { message }) => {
            assert!(message.contains("not a pairing ticket"), "{message}");
        }
        other => panic!("expected an error, got {other:?}"),
    }
    let twice = b.node.accept_ticket(a.node.ticket(true).unwrap());
    assert!(matches!(twice, Err(VaultError::Exists { .. })));
    let own = a.node.accept_ticket(a.node.ticket(false).unwrap());
    assert!(matches!(own, Err(VaultError::Invalid { .. })));
}

#[test]
fn a_stopped_node_refuses_every_call() {
    let a = side(&[("Newsletter.md", "Hello.\n")], RelaySetting::Off);
    a.node.stop();
    a.node.stop();
    assert!(matches!(a.node.id(), Err(VaultError::Invalid { .. })));
    assert!(a.node.ticket(false).is_err());
    assert!(a.node.sync_now().is_err());
    assert!(a.node.state().is_err());
    // The vault itself still works.
    assert_eq!(a.vault.snapshot().unwrap().len(), 1);
}

#[test]
fn a_node_started_as_a_device_is_seen_as_one_and_can_be_relabelled() {
    let dir = tempfile::tempdir().unwrap();
    std::fs::write(dir.path().join("Newsletter.md"), "A note.\n").unwrap();
    let index = tempfile::tempdir().unwrap();
    let vault = open_vault(
        dir.path().to_str().unwrap().to_string(),
        index.path().join("index.db").to_str().unwrap().to_string(),
    )
    .unwrap();
    let a = start_node_as(
        Arc::clone(&vault),
        RelaySetting::Off,
        Some("mac".to_string()),
        Some("Study".to_string()),
    )
    .unwrap();
    let b = side(&[], RelaySetting::Off);
    a.sync_now().unwrap();
    b.node.accept_ticket(a.ticket(true).unwrap()).unwrap();
    b.node.sync_now().unwrap();
    let seen = &b.node.peers().unwrap()[0];
    assert_eq!(seen.kind.as_deref(), Some("mac"));
    assert_eq!(seen.name.as_deref(), Some("Study"));
    assert_eq!(seen.label, None);
    b.node
        .rename_peer(seen.id.clone(), Some("Desk".to_string()))
        .unwrap();
    assert_eq!(b.node.peers().unwrap()[0].label.as_deref(), Some("Desk"));
    b.node.rename_peer(seen.id.clone(), None).unwrap();
    assert_eq!(b.node.peers().unwrap()[0].label, None);
    // b said nothing about itself; a still syncs with it and sees no kind.
    let seen_by_a = &a.peers().unwrap()[0];
    assert_eq!(seen_by_a.kind, None);
    drop(b);
    a.stop();
}

#[derive(Clone, Default)]
struct Heard(Arc<Mutex<Vec<PeerEvent>>>);

impl PeerListener for Heard {
    fn event(&self, event: PeerEvent) {
        self.0.lock().unwrap().push(event);
    }
}

#[test]
fn a_listener_hears_the_ticket_go_and_the_size_of_a_first_fetch() {
    let a = side(
        &[
            ("Newsletter.md", "A note.\n"),
            ("Gift ideas.md", "Candles.\n"),
        ],
        RelaySetting::Off,
    );
    let b = side(&[], RelaySetting::Off);
    a.node.sync_now().unwrap();
    let heard_by_a = Heard::default();
    let heard_by_b = Heard::default();
    a.node.listen(Box::new(heard_by_a.clone())).unwrap();
    b.node.listen(Box::new(heard_by_b.clone())).unwrap();
    b.node.accept_ticket(a.node.ticket(true).unwrap()).unwrap();
    b.node.sync_now().unwrap();
    let b_id = b.node.id().unwrap();
    assert_eq!(
        heard_by_a.0.lock().unwrap().clone(),
        vec![
            PeerEvent::TicketRedeemed { by: b_id.clone() },
            PeerEvent::PeerJoined { id: b_id },
        ]
    );
    assert_eq!(
        heard_by_b.0.lock().unwrap().clone(),
        vec![
            PeerEvent::FetchProgress {
                received: 0,
                total: Some(2),
            },
            PeerEvent::FetchProgress {
                received: 2,
                total: Some(2),
            },
        ]
    );
    // A stopped node tells no one anything more, and refuses a new listener.
    a.node.stop();
    assert!(a.node.listen(Box::new(Heard::default())).is_err());
}
