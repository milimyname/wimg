# SQLite Schema

```sql
CREATE TABLE accounts (
  id          TEXT PRIMARY KEY,        -- "comdirect-main", "scalable", etc.
  name        TEXT NOT NULL,           -- "Comdirect Girokonto"
  type        TEXT NOT NULL,           -- checking, investment, savings, cash
  currency    TEXT DEFAULT 'EUR',
  owner       TEXT,                    -- "Komiljon", "Familie", "Kind"
  color       TEXT,                    -- hex, for UI differentiation
  updated_at  INTEGER NOT NULL
);

CREATE TABLE transactions (
  id          TEXT PRIMARY KEY,        -- hash of date+desc+amount+account
  date        TEXT NOT NULL,           -- ISO: 2026-02-14
  description TEXT NOT NULL,
  amount      INTEGER NOT NULL,        -- cents, negative = expense
  currency    TEXT DEFAULT 'EUR',
  category    TEXT,
  account     TEXT REFERENCES accounts(id), -- FK to accounts table
  raw         TEXT,                    -- original CSV row
  updated_at  INTEGER NOT NULL         -- unix ms, last write wins
);

CREATE TABLE categories (
  name        TEXT PRIMARY KEY,
  color       TEXT NOT NULL,           -- hex
  icon        TEXT,                    -- emoji
  updated_at  INTEGER NOT NULL
);

CREATE TABLE debts (
  id          TEXT PRIMARY KEY,
  name        TEXT NOT NULL,           -- "WSW Strom", "FOM", "Klarna"
  total       INTEGER NOT NULL,        -- cents
  paid        INTEGER DEFAULT 0,       -- cents
  monthly     INTEGER,                 -- cents, optional
  updated_at  INTEGER NOT NULL
);

CREATE TABLE rules (
  pattern     TEXT NOT NULL,           -- "REWE" → matches description
  category    TEXT NOT NULL,
  priority    INTEGER DEFAULT 0,
  updated_at  INTEGER NOT NULL
);

CREATE TABLE snapshots (
  id          TEXT PRIMARY KEY,        -- "2026-03"
  date        TEXT NOT NULL,           -- "2026-03-01"
  net_worth   INTEGER NOT NULL DEFAULT 0,
  income      INTEGER NOT NULL DEFAULT 0,
  expenses    INTEGER NOT NULL DEFAULT 0,
  tx_count    INTEGER NOT NULL DEFAULT 0,
  breakdown   TEXT NOT NULL DEFAULT '[]',  -- by_category JSON
  updated_at  INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE meta (
  key         TEXT PRIMARY KEY,
  value       TEXT NOT NULL
  -- last_sync, schema_version, etc.
);
```
