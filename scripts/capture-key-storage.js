#!/usr/bin/env node
/**
 * Reporter for capture-key-storage.ps1. Reads (readonly) the AnythingLLM db shape,
 * .env, and storage file metadata; emits one JSON line to stdout. Never emits
 * key-like values: they are reduced to {len, sha256-prefix} so before/after
 * snapshots can be diffed safely.
 */
'use strict';
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const { DatabaseSync } = require('node:sqlite');

function arg(name) {
  const i = process.argv.indexOf(name);
  return i >= 0 && i + 1 < process.argv.length ? process.argv[i + 1] : undefined;
}

const storageDir = arg('--storage-dir');
const envFile = arg('--env-file');
const label = arg('--label') || '';

const report = {
  ok: false,
  label,
  capturedAt: new Date().toISOString(),
  storageDir,
  error: null,
};

function emit() { console.log(JSON.stringify(report)); }
process.on('uncaughtException', (e) => { report.error = String(e.message || e); emit(); process.exit(0); });

function looksKeyLike(s) {
  if (typeof s !== 'string' || s.length < 16) return false;
  return /^(sk-|or-|ey-|aiza|glpat|ghp_|sk-or-v1)/i.test(s.trim()) ||
         /^[A-Za-z0-9_-]{32,64}$/.test(s.trim());
}
function redact(raw) {
  if (raw === null || typeof raw !== 'string' || raw.length === 0) return raw;
  if (!looksKeyLike(raw)) return raw;
  return { __redacted: 'key', len: raw.trim().length, sha256: crypto.createHash('sha256').update(raw.trim()).digest('hex').slice(0, 12) };
}

// --- db ---------------------------------------------------------------------
const dbPath = path.join(storageDir, 'anythingllm.db');
if (!fs.existsSync(dbPath)) { report.error = `db not found: ${dbPath}`; emit(); process.exit(0); }

// Fail fast if app holds exclusive lock (test open for read).
let fd = null;
try {
  fd = fs.openSync(dbPath, 'r');
} catch (e) {
  report.error = 'db is locked - close AnythingLLM fully (including tray) and rerun';
  emit();
  process.exit(0);
} finally {
  if (fd !== null) { try { fs.closeSync(fd); } catch (_) {} }
}

let dbReport;
try {
  const db = new DatabaseSync(dbPath, { readOnly: true });
  try {
    const tables = db.prepare(`SELECT name FROM sqlite_master WHERE type='table'`).all().map((r) => r.name);
    dbReport = { tableCount: tables.length, tables: {} };
    for (const t of tables) {
      try {
        const cols = db.prepare(`PRAGMA table_info("${t}")`).all().map((c) => c.name);
        let rows = [];
        try { rows = db.prepare(`SELECT * FROM "${t}" LIMIT 400`).all(); } catch (inner) {
          dbReport.tables[t] = { columns: cols, error: String(inner.message || inner) };
          continue;
        }
        dbReport.tables[t] = {
          columns: cols,
          rows: rows.map((r) => { const o = {}; for (const [k, v] of Object.entries(r)) o[k] = v === null ? null : redact(v); return o; }),
        };
      } catch (inner) { dbReport.tables[t] = { error: String(inner.message || inner) }; }
    }
  } finally { try { db.close(); } catch (_) {} }
} catch (e) {
  report.error = `db read failed: ${e.message || e}`; emit(); process.exit(0);
}
report.database = dbReport;

// --- .env -------------------------------------------------------------------
const envReport = [];
if (fs.existsSync(envFile)) {
  for (const line of fs.readFileSync(envFile, 'utf8').split(/\r?\n/)) {
    const m = /^\s*([^#=]+)=(.*)$/.exec(line);
    if (m) {
      const name = m[1].trim(); const val = m[2].trim();
      // Name-first redaction: any var whose name mentions KEY/TOKEN/SECRET/API is
      // redacted no matter what its value looks like (shape heuristics are not enough).
      const nameSensitive = /(api|key|token|secret|signature|sig)/i.test(name);
      const looksKey = nameSensitive ||
        (val.length >= 20 && (/^(sk-|or-|ey-|aiza|glpat|ghp_)/i.test(val) || (!/\s/.test(val) && val.length >= 32 && /^[A-Za-z0-9_-]+$/.test(val) && !val.includes(':'))));
      envReport.push([name, looksKey ? { __redacted: 'key', len: val.length } : val]);
    } else {
      envReport.push(['raw-line', line]);
    }
  }
}
report.envFile = envReport;

// --- storage file metadata ---------------------------------------------------
const files = [];
const walk = (dir) => {
  let entries = [];
  try { entries = fs.readdirSync(dir, { withFileTypes: true }); } catch (_) { return; }
  for (const e of entries) {
    const full = path.join(dir, e.name);
    if (e.isDirectory()) walk(full);
    else {
      try {
        const st = fs.statSync(full);
        files.push({ name: path.relative(storageDir, full), length: st.size, lastWrite: st.mtime.toISOString() });
      } catch (_) {}
    }
  }
};
walk(storageDir);
report.storageFiles = files;
report.ok = true;
emit();
