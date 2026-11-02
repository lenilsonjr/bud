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
