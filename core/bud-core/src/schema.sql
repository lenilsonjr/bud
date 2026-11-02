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
