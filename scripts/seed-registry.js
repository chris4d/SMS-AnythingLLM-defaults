#!/usr/bin/env node
/**
 * Seeds the SMS Toolkit baseline Model Router into the AnythingLLM Desktop db,
 * plus non-secret .env defaults. Never logs or prints key values.
 * Always exits 0 on seed problems, recording issues in install-status.json.
 *
 * Node v22 with node:sqlite (--experimental-sqlite). No external deps.
 */
'use strict';

const fs = require('fs');
const path = require('path');

function readJson(p) {
  return JSON.parse(fs.readFileSync(p, 'utf8'));
}

function nowStamp() {
  return new Date().toISOString().replace('T', ' ').replace('Z', '');
}

function statusReport(outPath, entry) {
  let cur = { util: '_anythingllm-defaults', steps: [] };
  try { if (fs.existsSync(outPath)) cur = JSON.parse(fs.readFileSync(outPath, 'utf8')); } catch (_) {}
  cur.steps = (cur.steps || []).filter((s) => s.name !== entry.name).concat(entry);
  fs.writeFileSync(outPath, JSON.stringify(cur, null, 2), 'utf8');
}

function main() {
  // Flags:
  //  --storage-dir <dir>    e.g. %APPDATA%\anythingllm-desktop\storage
  //  --seed-file <json>     literal seed data (no secrets)
  //  --app-dir <dir>        {app} for pending-seed.json
  //  --status-file <json>   install-status.json path
  //  --apikeys-path <file>  suite-provided; recorded only by reference (never read/logged here)
  const args = process.argv.slice(2);
  const opt = (name) => {
    const i = args.indexOf(name);
    return i >= 0 && i + 1 < args.length ? args[i + 1] : undefined;
  };
  const storageDir = opt('--storage-dir');
  const seedFile = opt('--seed-file');
  const appDir = opt('--app-dir');
  const statusFile = opt('--status-file') || 'install-status.json';
  const apikeysPath = opt('--apikeys-path');
  const stamp = nowStamp();

  if (!storageDir || !seedFile || !appDir) {
    statusReport(statusFile, {
      name: 'seed-model-router',
      ok: false,
      action: 'missing-args',
      message: `${stamp}: storage-dir/seed-file/app-dir not all supplied.`,
    });
    return 0;
  }
  if (!fs.existsSync(storageDir)) fs.mkdirSync(storageDir, { recursive: true });
  const dbPath = path.join(storageDir, 'anythingllm.db');
  const seed = readJson(seedFile);

  if (fs.existsSync(dbPath)) {
    let result;
    try {
      result = doSeed(storageDir, seed, stamp);
    } catch (e) {
      result = { ok: true, action: 'report-error', message: `${stamp}: seed error (non-blocking): ${e.message || String(e)}` };
    }
    statusReport(statusFile, { name: 'seed-model-router', ok: result.ok, action: result.action, message: result.message });
  } else {
    // First-launch path: write pending marker; the launcher shim re-invokes us
    // after the app has created the db.
    writePending(seed, storageDir, apikeysPath, appDir, stamp);
    statusReport(statusFile, { name: 'seed-model-router', ok: true, action: 'pending-first-launch', message: `${stamp}: db not found; pending-seed.json written for first-launch shim.` });
  }
  return 0;
}

function writePending(seed, storageDir, apikeysPath, appDir, stamp) {
  fs.writeFileSync(path.join(appDir, 'pending-seed.json'), JSON.stringify({
    used: false,
    created: stamp,
    appDir,
    storageDir,
    apikeysPath: apikeysPath || '',
    seedFile: path.resolve(seed.pendingSeedFile || ''),
    seed: { envDefaults: seed.envDefaults, settings: seed.settings },
  }, null, 2));
}

function doSeed(storageDir, seed, stamp) {
  const { DatabaseSync } = require('node:sqlite');
  const dbPath = path.join(storageDir, 'anythingllm.db');
  const db = new DatabaseSync(dbPath, { open: true });
  try {
    // Table drift check — AnythingLLM could rename these tables in future versions.
    let tables = [];
    try {
      tables = db.prepare(`SELECT name FROM sqlite_master WHERE type='table'`).all().map((r) => r.name);
    } catch (_) { tables = []; }
    for (const t of ['model_routers', 'model_router_rules', 'system_settings']) {
      if (!tables.includes(t)) {
        return { ok: false, action: 'report-error', message: `${stamp}: missing expected table ${t} (AnythingLLM schema drift?) — recorded, not blocking.` };
      }
    }

    const settings = new Map(db.prepare(`SELECT key, value FROM system_settings`).all().map((r) => [r.key, r.value]));
    if (settings.get('_seeded_by_sms_toolkit')) {
      return { ok: true, action: 'skipped', message: `${stamp}: seed marker present; skipping.` };
    }

    // Insert only columns that actually exist; any we don't recognize (e.g. timestamp
    // columns) are left for the db defaults / the app itself to manage.
    const quoteId = (id) => `"${id.replace(/"/g, '""')}"`;
    const colsOf = (table) => db.prepare(`PRAGMA table_info(${table})`).all().map((c) => c.name);
    const pick = (table, obj) => {
      const cols = colsOf(table);
      const names = Object.keys(obj).filter((k) => cols.includes(k));
      return {
        cols: names.map(quoteId).join(', '),
        ph: names.map(() => '?').join(', '),
        vals: names.map((k) => obj[k]),
      };
    };
    const insertRow = (table, obj) => {
      const { cols, ph, vals } = pick(table, obj);
      db.prepare(`INSERT INTO ${table} (${cols}) VALUES (${ph})`).run(...vals);
    };

    db.exec('BEGIN');
    try {
      // Non-secret .env defaults (never key material). Written as a complement file;
      // AnythingLLM regenerates its own .env each boot, so we don't race it.
      const envDefaults = seed.envDefaults || {};
      const envPath = path.join(storageDir, '.env.sms-defaults');
      let envText = '';
      try { envText = fs.readFileSync(envPath, 'utf8'); } catch (_) { envText = ''; }
      for (const [k, v] of Object.entries(envDefaults)) {
        const re = new RegExp(`^${k.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}=.*$`, 'm');
        if (re.test(envText)) envText = envText.replace(re, `${k}=${v}`);
        else envText += `\n${k}=${v}`;
      }
      fs.writeFileSync(envPath, envText.trim() + '\n');

      const router = seed.router;
      let routerId;
      const existing = db.prepare(`SELECT id FROM model_routers WHERE name=?`).all(router.name);
      if (existing.length) {
        routerId = existing[0].id;
      } else {
        insertRow('model_routers', {
          name: router.name,
          description: router.description || '',
          fallback_provider: router.fallback_provider,
          fallback_model: router.fallback_model,
          cooldown_seconds: router.cooldown_seconds || 300,
          created_by: 'sms_toolkit',
        });
        routerId = Number(db.prepare(`SELECT last_insert_rowid() AS id`).get().id);
      }

      // Rules: replace our own rows only, under this router.
      db.prepare(`DELETE FROM model_router_rules WHERE router_id=?`).run(routerId);
      for (const r of seed.rules) {
        insertRow('model_router_rules', {
          router_id: routerId,
          enabled: r.enabled,
          priority: r.priority,
          type: r.type,
          title: r.title,
          description: r.description || '',
          condition_logic: r.condition_logic || 'OR',
          conditions: JSON.stringify(r.conditions || []),
          route_provider: r.route_provider,
          route_model: r.route_model,
        });
      }

      // Idempotency marker + first-run wizard skip.
      const setSetting = db.prepare(`INSERT INTO system_settings (key, value) VALUES (?, ?) ON CONFLICT(key) DO UPDATE SET value=excluded.value`);
      for (const s of seed.settings || []) setSetting.run(s.key, s.value);

      db.exec('COMMIT');
      return { ok: true, action: 'seeded', message: `${stamp}: router '${router.name}' and ${seed.rules.length} rules seeded; onboarding skipped; seed marker set.` };
    } catch (inner) {
      try { db.exec('ROLLBACK'); } catch (_) {}
      throw inner;
    }
  } finally {
    try { db.close(); } catch (_) {}
  }
}

process.exit(main());
