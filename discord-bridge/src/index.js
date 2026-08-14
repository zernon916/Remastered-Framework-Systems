/**
 * RFS Discord Bridge — Streamer mode vote dropper
 *
 * Runs on the same PC as the Scrap Mechanic host. Lua cannot HTTP, so this
 * process writes vote.json into a path RfsStreamer.lua polls.
 *
 * Usage:
 *   copy .env.example → .env, set DISCORD_TOKEN + CLIENT_ID (+ GUILD_ID)
 *   npm install && npm run register && npm start
 */

'use strict';

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
require('dotenv').config({ path: path.join(__dirname, '..', '.env') });

const { Client, GatewayIntentBits } = require('discord.js');
const { registerCommands } = require('./register-commands');
const { checkVotePermission, describeLocks } = require('./permissions');
const chatRelay = require('./chat-relay');

const TOKEN = process.env.DISCORD_TOKEN || '';
const CLIENT_ID = process.env.CLIENT_ID || process.env.DISCORD_CLIENT_ID || '';
const VOTE_COOLDOWN_SEC = Math.max(0, Number(process.env.VOTE_COOLDOWN_SEC) || 15);

const ROOT = path.join(__dirname, '..');
const DEFAULT_DROP = path.join(ROOT, 'inbox', 'vote.json');
const DROP_PATH = process.env.DROP_PATH
  ? path.resolve(process.env.DROP_PATH)
  : DEFAULT_DROP;
const ALLOWLIST_PATH = path.join(ROOT, 'config', 'allowlist.json');

/** @type {{ units: Set<string>, itemsByAlias: Map<string, string>, itemUuids: Set<string> }} */
let allowlist = { units: new Set(), itemsByAlias: new Map(), itemUuids: new Set() };
/** @type {Map<string, number>} */
const lastVoteAt = new Map();

function loadAllowlist() {
  const raw = JSON.parse(fs.readFileSync(ALLOWLIST_PATH, 'utf8'));
  const units = new Set(
    (raw.units || []).map((u) => String(u).toLowerCase().trim()).filter(Boolean)
  );
  const itemsByAlias = new Map();
  const itemUuids = new Set();
  for (const entry of raw.items || []) {
    if (!entry || !entry.uuid) continue;
    const uuid = String(entry.uuid).toLowerCase().trim();
    itemUuids.add(uuid);
    if (entry.alias) {
      itemsByAlias.set(String(entry.alias).toLowerCase().trim(), uuid);
    }
  }
  allowlist = { units, itemsByAlias, itemUuids };
}

function ensureInboxDir(filePath) {
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
}

/**
 * Atomic write: temp file in same directory, then rename.
 * Avoids RfsStreamer reading a partial JSON file.
 */
function atomicWriteJson(filePath, obj) {
  ensureInboxDir(filePath);
  const dir = path.dirname(filePath);
  const tmp = path.join(
    dir,
    `.${path.basename(filePath)}.${process.pid}.${Date.now()}.tmp`
  );
  const body = JSON.stringify(obj, null, 2);
  fs.writeFileSync(tmp, body, 'utf8');
  try {
    fs.renameSync(tmp, filePath);
  } catch (err) {
    // Windows: rename over existing can fail; replace explicitly.
    try {
      fs.unlinkSync(filePath);
    } catch (_) {
      /* missing is fine */
    }
    fs.renameSync(tmp, filePath);
  }
}

function makeId() {
  if (typeof crypto.randomUUID === 'function') {
    return crypto.randomUUID();
  }
  return `${Date.now()}-${crypto.randomBytes(4).toString('hex')}`;
}

/**
 * Drop schema (documented in README):
 * {
 *   id, action: "spawn"|"give", unit, item, amount,
 *   source: "discord", voter, createdAt
 * }
 * Legacy mirrors kept for older readers: ts, uuid, quantity
 */
function writeVote(payload) {
  const createdAt = new Date().toISOString();
  const body = {
    id: makeId(),
    action: payload.action,
    unit: payload.unit ?? null,
    item: payload.item ?? null,
    amount: payload.amount ?? 1,
    source: 'discord',
    voter: payload.voter ?? null,
    createdAt,
    // Legacy compatibility for older RfsStreamer / tools
    ts: Date.now(),
    uuid: payload.action === 'give' ? payload.item : undefined,
    quantity: payload.amount ?? 1,
  };
  // Drop undefined keys from legacy mirrors only
  if (body.uuid === undefined) delete body.uuid;

  atomicWriteJson(DROP_PATH, body);
  return body;
}

function resolveItem(raw) {
  if (!raw) return null;
  const key = String(raw).toLowerCase().trim();
  if (allowlist.itemsByAlias.has(key)) {
    return allowlist.itemsByAlias.get(key);
  }
  if (allowlist.itemUuids.has(key)) {
    return key;
  }
  // Accept raw UUID form if it looks like one and is on the allowlist already checked;
  // also allow exact UUID match with original casing normalized.
  const uuidRe =
    /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
  if (uuidRe.test(key) && allowlist.itemUuids.has(key)) {
    return key;
  }
  return null;
}

function canVote(interaction) {
  const perm = checkVotePermission(interaction);
  if (!perm.ok) return perm;

  const uid = interaction.user.id;
  const now = Date.now();
  const prev = lastVoteAt.get(uid) || 0;
  const waitMs = VOTE_COOLDOWN_SEC * 1000;
  if (waitMs > 0 && now - prev < waitMs) {
    const left = Math.ceil((waitMs - (now - prev)) / 1000);
    return { ok: false, reason: `Cooldown: wait ${left}s before another vote.` };
  }
  return { ok: true };
}

async function handleVote(interaction) {
  const gate = canVote(interaction);
  if (!gate.ok) {
    await interaction.reply({ content: gate.reason, ephemeral: true });
    return;
  }

  // Reload allowlist each vote so hosts can edit without restarting.
  try {
    loadAllowlist();
  } catch (err) {
    await interaction.reply({
      content: `Allowlist error (${ALLOWLIST_PATH}): ${err.message}`,
      ephemeral: true,
    });
    return;
  }

  const action = interaction.options.getString('action', true);
  const amount = interaction.options.getInteger('amount') || 1;
  const unitRaw = interaction.options.getString('unit');
  const itemRaw = interaction.options.getString('item');

  let unit = null;
  let item = null;

  if (action === 'spawn') {
    const key = String(unitRaw || 'farmbot').toLowerCase().trim();
    if (!allowlist.units.has(key)) {
      const sample = [...allowlist.units].slice(0, 8).join(', ');
      await interaction.reply({
        content: `Unknown unit \`${key}\`. Allowed: ${sample}${
          allowlist.units.size > 8 ? ', …' : ''
        } (edit config/allowlist.json).`,
        ephemeral: true,
      });
      return;
    }
    unit = key;
  } else if (action === 'give') {
    if (!itemRaw) {
      await interaction.reply({
        content:
          'give requires `item` (alias or UUID from config/allowlist.json). Example: `/vote action:give item:farmers amount:1`',
        ephemeral: true,
      });
      return;
    }
    item = resolveItem(itemRaw);
    if (!item) {
      const aliases = [...allowlist.itemsByAlias.keys()].slice(0, 8).join(', ');
      await interaction.reply({
        content: `Unknown item \`${itemRaw}\`. Allowed aliases: ${aliases || '(none)'}.`,
        ephemeral: true,
      });
      return;
    }
  } else {
    await interaction.reply({ content: 'Unknown action.', ephemeral: true });
    return;
  }

  try {
    const written = writeVote({
      action,
      unit,
      item,
      amount,
      voter: interaction.user.id,
    });
    lastVoteAt.set(interaction.user.id, Date.now());
    await interaction.reply({
      content:
        `Vote written.\n` +
        `\`\`\`json\n${JSON.stringify(written, null, 2)}\n\`\`\`\n` +
        `File: \`${DROP_PATH}\`\n` +
        `In-game: Streamer ON + host world → RfsStreamer applies on next poll.`,
      ephemeral: true,
    });
  } catch (err) {
    await interaction.reply({
      content: `Failed to write vote file: ${err.message}`,
      ephemeral: true,
    });
  }
}

async function main() {
  if (process.argv.includes('--register')) {
    await registerCommands();
    return;
  }

  if (!TOKEN) {
    console.error('Missing DISCORD_TOKEN. Copy .env.example to .env and set your bot token.');
    process.exit(1);
  }

  try {
    loadAllowlist();
  } catch (err) {
    console.warn(`[rfs-discord-bridge] allowlist load failed: ${err.message}`);
  }

  const locks = describeLocks();
  ensureInboxDir(DROP_PATH);
  console.log(`[rfs-discord-bridge] vote drop path: ${DROP_PATH}`);
  console.log(
    `[rfs-discord-bridge] cooldown=${VOTE_COOLDOWN_SEC}s everyone=${locks.allowEveryoneVotes}` +
      ` channel=${locks.voteChannelId || 'any'} role=${locks.streamerRoleId || 'none'}`
  );
  console.log(
    '[rfs-discord-bridge] Run on the same PC as the SM host. Enable Streamer in /gensettings.'
  );

  if (CLIENT_ID) {
    try {
      await registerCommands();
    } catch (err) {
      console.warn('[rfs-discord-bridge] command register failed:', err.message);
    }
  }

  const intents = [GatewayIntentBits.Guilds, ...chatRelay.requiredIntents()];
  const client = new Client({ intents });

  client.once('ready', () => {
    console.log(`[rfs-discord-bridge] logged in as ${client.user.tag}`);
  });

  client.on('interactionCreate', async (interaction) => {
    if (!interaction.isChatInputCommand()) return;

    try {
      if (interaction.commandName === 'ping') {
        await interaction.reply({
          content: 'Pong — RFS Discord bridge is online.',
          ephemeral: true,
        });
        return;
      }
      if (interaction.commandName === 'vote') {
        await handleVote(interaction);
      }
    } catch (err) {
      console.error('[rfs-discord-bridge] interaction error:', err);
      if (interaction.deferred || interaction.replied) {
        await interaction.followUp({
          content: `Error: ${err.message}`,
          ephemeral: true,
        }).catch(() => {});
      } else {
        await interaction.reply({
          content: `Error: ${err.message}`,
          ephemeral: true,
        }).catch(() => {});
      }
    }
  });

  chatRelay.attachChatRelay(client);

  await client.login(TOKEN);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
