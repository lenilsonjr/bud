-- One row per bud. The index is derived from the folder and disposable (ADR-001).
CREATE TABLE IF NOT EXISTS buds (
    path      TEXT PRIMARY KEY NOT NULL,
    parent    TEXT,
    title     TEXT NOT NULL,
    kind      TEXT NOT NULL,
    state     TEXT,
    when_date TEXT,
    due       TEXT,
    pinned    INTEGER NOT NULL DEFAULT 0,
    created   TEXT,
    source    TEXT,
    body      TEXT NOT NULL DEFAULT '',
    mtime     INTEGER NOT NULL,
    place     TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS buds_parent ON buds(parent);
CREATE INDEX IF NOT EXISTS buds_place ON buds(place);

-- Full-text search over title and body. The text stays in `buds`; the triggers keep this index in
-- step with every insert, update and delete there, whoever makes it (a scan, a write, the watcher).
CREATE VIRTUAL TABLE IF NOT EXISTS buds_fts USING fts5(
    title, body, content='buds', content_rowid='rowid'
);
CREATE TRIGGER IF NOT EXISTS buds_fts_insert AFTER INSERT ON buds BEGIN
    INSERT INTO buds_fts(rowid, title, body) VALUES (new.rowid, new.title, new.body);
END;
CREATE TRIGGER IF NOT EXISTS buds_fts_delete AFTER DELETE ON buds BEGIN
    INSERT INTO buds_fts(buds_fts, rowid, title, body)
    VALUES ('delete', old.rowid, old.title, old.body);
END;
CREATE TRIGGER IF NOT EXISTS buds_fts_update AFTER UPDATE OF title, body ON buds BEGIN
    INSERT INTO buds_fts(buds_fts, rowid, title, body)
    VALUES ('delete', old.rowid, old.title, old.body);
    INSERT INTO buds_fts(rowid, title, body) VALUES (new.rowid, new.title, new.body);
END;

-- Every [[link]] written in a body, under the rowid of the bud it is written in: an upsert keeps
-- the rowid, and so does a rename or a move, so the links follow their bud. The target is the
-- text between the brackets, resolved when it is read (links module).
CREATE TABLE IF NOT EXISTS links (
    source   INTEGER NOT NULL,
    target   TEXT NOT NULL,
    label    TEXT,
    position INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS links_source ON links(source);
CREATE INDEX IF NOT EXISTS links_target ON links(target COLLATE NOCASE);
CREATE TRIGGER IF NOT EXISTS links_delete AFTER DELETE ON buds BEGIN
    DELETE FROM links WHERE source = old.rowid;
END;

-- Each tag a bud carries, once, under its rowid like its links; origin is `frontmatter` or
-- `body` (tags module).
CREATE TABLE IF NOT EXISTS bud_tags (
    source INTEGER NOT NULL,
    tag    TEXT NOT NULL COLLATE NOCASE,
    origin TEXT NOT NULL,
    UNIQUE (source, tag)
);
CREATE INDEX IF NOT EXISTS bud_tags_tag ON bud_tags(tag);
CREATE TRIGGER IF NOT EXISTS bud_tags_delete AFTER DELETE ON buds BEGIN
    DELETE FROM bud_tags WHERE source = old.rowid;
END;

-- One CRDT document per bud (sync module). Unlike `buds` this is not derived from the folder:
-- the document bytes carry history, so a schema change never drops these tables. `known_text` is
-- the last full file text the document knew; a file that differs from it was edited outside.
CREATE TABLE IF NOT EXISTS docs (
    path       TEXT PRIMARY KEY NOT NULL,
    id         TEXT NOT NULL UNIQUE,
    bytes      BLOB NOT NULL,
    known_text TEXT NOT NULL DEFAULT ''
);
-- The tree document of all buds: names, parents and trashing, keyed by bud identity.
CREATE TABLE IF NOT EXISTS tree_doc (
    id    INTEGER PRIMARY KEY CHECK (id = 1),
    bytes BLOB NOT NULL
);

-- Peer transport. Like `docs`, these hold what cannot be derived from the folder, so a schema
-- change never drops them. The vault folder holds none of it.
-- The key every document and message is encrypted with, made on first use and replaced once by
-- the key of the first ticket accepted.
CREATE TABLE IF NOT EXISTS peer_key (
    id  INTEGER PRIMARY KEY CHECK (id = 1),
    key BLOB NOT NULL
);
-- The peers this vault remembers: node id in hex, the relay setting of the ticket, and the direct
-- addresses it carried, one per line.
CREATE TABLE IF NOT EXISTS peers (
    node  TEXT PRIMARY KEY NOT NULL,
    relay TEXT NOT NULL,
    addrs TEXT NOT NULL DEFAULT '',
    added INTEGER NOT NULL
);
-- Nodes this vault removed: they are turned away even when they prove the vault key.
CREATE TABLE IF NOT EXISTS peer_denied (
    node TEXT PRIMARY KEY NOT NULL
);
-- The tickets this vault issued and that nobody redeemed yet, with when each was made in
-- milliseconds since the epoch; a ticket leaves the table the first time it is redeemed, or when
-- it is older than its lifetime.
CREATE TABLE IF NOT EXISTS tickets_issued (
    id     BLOB PRIMARY KEY NOT NULL,
    issued INTEGER NOT NULL
);
-- Peers the last key rotation could not move: they hold the old key until a session with them
-- works again.
CREATE TABLE IF NOT EXISTS peer_missed (
    node TEXT PRIMARY KEY NOT NULL
);
-- The ticket this vault accepted from a peer, until the first session with that peer worked.
CREATE TABLE IF NOT EXISTS peer_ticket (
    node   TEXT PRIMARY KEY NOT NULL,
    ticket BLOB NOT NULL
);
-- When each peer last took part in a session, in seconds since the epoch.
CREATE TABLE IF NOT EXISTS peer_seen (
    node TEXT PRIMARY KEY NOT NULL,
    seen INTEGER NOT NULL
);
-- What each peer said it is in its last session: its kind (mac, iphone, ipad, tv) and the name
-- its system gives it. Either may be missing from a build that does not send them.
CREATE TABLE IF NOT EXISTS peer_identity (
    node TEXT PRIMARY KEY NOT NULL,
    kind TEXT,
    name TEXT
);
-- The label this vault gave a peer, kept apart from the name the peer sends.
CREATE TABLE IF NOT EXISTS peer_label (
    node  TEXT PRIMARY KEY NOT NULL,
    label TEXT NOT NULL
);
