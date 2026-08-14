/**
 * Chat relay — Discord → local file drop → in-game (Phase B).
 *
 * When CHAT_RELAY_ENABLED=true, append channel messages to:
 *   inbox/chat.jsonl       — append-only JSONL log (tooling / history)
 *   inbox/chat_inbox.json  — JSON { messages: [...] } for RfsChatRelay.lua
 *                            (SM sm.json.open cannot parse JSONL)
 *
 * Env:
 *   CHAT_RELAY_ENABLED  — default false
 *   CHAT_CHANNEL_ID     — if set, only listen in this channel; if unset while
 *                         relay is enabled, ignore all messages (safe no-op)
 *   CHAT_RELAY_PATH     — optional absolute path (default: ../inbox/chat.jsonl)
 *
 * Ignores bots. Per-user rate limit avoids flooding the drop file.
 * Line shape: { id, ts, author, content, user, text, ... } — Lua accepts both
 * author/content and user/text.
 */

'use strict';

const fs = require('fs');
const path = require('path');
const { GatewayIntentBits } = require('discord.js');
const { envFlag } = require('./permissions');

const DEFAULT_CHAT_PATH = path.join(__dirname, '..', 'inbox', 'chat.jsonl');
/** Soft cap of messages kept in chat_inbox.json (Lua polls this). */
const INBOX_MAX_MESSAGES = 400;

/** Min ms between accepted messages from the same author (anti-flood). */
const RATE_LIMIT_MS = 1500;
/** Soft cap on content length stored per line. */
const MAX_CONTENT_LEN = 400;

function isEnabled() {
  return envFlag('CHAT_RELAY_ENABLED', false);
}

function chatDropPath() {
  const raw = (process.env.CHAT_RELAY_PATH || '').trim();
  return raw ? path.resolve(raw) : DEFAULT_CHAT_PATH;
}

function chatInboxPath(jsonlPath) {
  const base = jsonlPath || chatDropPath();
  const dir = path.dirname(base);
  const name = path.basename(base);
  if (/chat\.jsonl$/i.test(name)) {
    return path.join(dir, name.replace(/chat\.jsonl$/i, 'chat_inbox.json'));
  }
  return path.join(dir, 'chat_inbox.json');
}

function chatChannelId() {
  return (process.env.CHAT_CHANNEL_ID || '').trim();
}

/**
 * Extra intents when chat relay is on.
 * Also enable Message Content Intent in Developer Portal → Bot.
 */
function requiredIntents() {
  if (!isEnabled()) return [];
  return [GatewayIntentBits.GuildMessages, GatewayIntentBits.MessageContent];
}

function ensureParentDir(filePath) {
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
}

function atomicWriteJson(filePath, obj) {
  ensureParentDir(filePath);
  const dir = path.dirname(filePath);
  const tmp = path.join(
    dir,
    `.${path.basename(filePath)}.${process.pid}.${Date.now()}.tmp`
  );
  fs.writeFileSync(tmp, `${JSON.stringify(obj, null, 2)}\n`, 'utf8');
  try {
    fs.renameSync(tmp, filePath);
  } catch (err) {
    try {
      fs.unlinkSync(filePath);
    } catch (_) {
      /* ignore */
    }
    fs.renameSync(tmp, filePath);
  }
}

function parseJsonlMessages(jsonlPath) {
  if (!fs.existsSync(jsonlPath)) return [];
  let raw = '';
  try {
    raw = fs.readFileSync(jsonlPath, 'utf8');
  } catch (_) {
    return [];
  }
  const out = [];
  for (const line of raw.split(/\r?\n/)) {
    const t = line.trim();
    if (!t) continue;
    try {
      const obj = JSON.parse(t);
      if (obj && typeof obj === 'object') out.push(obj);
    } catch (_) {
      /* skip bad lines */
    }
  }
  return out;
}

/**
 * Rewrite chat_inbox.json from the JSONL log (capped).
 * RfsChatRelay.lua polls this via sm.json.open.
 */
function syncChatInbox(jsonlPath) {
  const filePath = jsonlPath || chatDropPath();
  let messages = parseJsonlMessages(filePath);
  if (messages.length > INBOX_MAX_MESSAGES) {
    messages = messages.slice(messages.length - INBOX_MAX_MESSAGES);
  }
  atomicWriteJson(chatInboxPath(filePath), {
    version: 1,
    updatedAt: Date.now(),
    messages,
  });
}

/**
 * Append one chat line + refresh inbox companion.
 * @returns {boolean} true if a line was written
 */
function appendChatLine(entry) {
  const filePath = chatDropPath();
  ensureParentDir(filePath);
  fs.appendFileSync(filePath, `${JSON.stringify(entry)}\n`, 'utf8');
  try {
    syncChatInbox(filePath);
  } catch (err) {
    console.warn('[rfs-discord-bridge] chat inbox sync failed:', err.message);
  }
  return true;
}

/**
 * Attach messageCreate listener. No-op when CHAT_RELAY_ENABLED is false.
 * @param {import('discord.js').Client} client
 */
function attachChatRelay(client) {
  if (!isEnabled()) {
    console.log('[rfs-discord-bridge] chat relay: disabled (CHAT_RELAY_ENABLED=false)');
    return;
  }

  const channelId = chatChannelId();
  const drop = chatDropPath();
  const inbox = chatInboxPath(drop);
  if (!channelId) {
    console.warn(
      '[rfs-discord-bridge] chat relay: enabled but CHAT_CHANNEL_ID unset — listening nowhere (safe).'
    );
  } else {
    console.log(`[rfs-discord-bridge] chat relay: channel ${channelId} → ${drop}`);
    console.log(`[rfs-discord-bridge] chat relay: Lua inbox companion → ${inbox}`);
    console.log(
      '[rfs-discord-bridge] chat relay: enable /gensettings → Discord chat relay in-game.'
    );
  }

  // Ensure companion exists even before first message (empty array).
  try {
    syncChatInbox(drop);
  } catch (err) {
    console.warn('[rfs-discord-bridge] chat inbox init failed:', err.message);
  }

  /** @type {Map<string, number>} */
  const lastByUser = new Map();

  client.on('messageCreate', (message) => {
    try {
      if (!message || message.author?.bot) return;
      if (!channelId || message.channelId !== channelId) return;

      const text = (message.content || '').trim();
      if (!text) return;

      const uid = message.author.id;
      const now = Date.now();
      const prev = lastByUser.get(uid) || 0;
      if (now - prev < RATE_LIMIT_MS) return;
      lastByUser.set(uid, now);

      const author = message.author.username || message.author.tag || 'Discord';
      const content = text.slice(0, MAX_CONTENT_LEN);

      appendChatLine({
        id: `${now}-${Math.random().toString(36).slice(2, 8)}`,
        ts: now,
        source: 'discord',
        direction: 'in',
        channel: channelId,
        // Preferred Phase B fields
        author,
        content,
        // Aliases (older example / tooling)
        user: author,
        text: content,
        channelId: message.channelId,
        authorId: uid,
        authorTag: message.author.tag,
      });
    } catch (err) {
      console.warn('[rfs-discord-bridge] chat relay append failed:', err.message);
    }
  });
}

module.exports = {
  isEnabled,
  chatDropPath,
  chatInboxPath,
  chatChannelId,
  requiredIntents,
  attachChatRelay,
  appendChatLine,
  syncChatInbox,
};
