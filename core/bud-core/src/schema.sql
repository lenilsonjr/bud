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
