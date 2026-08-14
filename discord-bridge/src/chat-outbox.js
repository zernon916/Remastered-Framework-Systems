/**
 * Chat outbox — game → Discord (Phase D).
 *
 * RfsChatOutbox.lua writes chat_outbox.json when Streamer + chat relay are on
 * and a player uses /say or /d. This module polls and posts new messages.
 *
 * Env:
 *   CHAT_OUTBOX_ENABLED  — default true when CHAT_RELAY_ENABLED (else false)
 *   CHAT_CHANNEL_ID      — preferred post target
 *   OUT_CHANNEL_ID       — fallback if CHAT_CHANNEL_ID unset
 *   CHAT_OUTBOX_PATH     — optional absolute path to chat_outbox.json
 *
 * Loop prevention: skip direction:"in", source:"discord", and bot-authored rows.
 */

'use strict';

const fs = require('fs');
const path = require('path');
const { envFlag } = require('./permissions');

const DEFAULT_OUTBOX = path.join(__dirname, '..', 'inbox', 'chat_outbox.json');
const POLL_MS = 1000;
const MAX_CONTENT = 400;

function isEnabled() {
  if (process.env.CHAT_OUTBOX_ENABLED !== undefined && process.env.CHAT_OUTBOX_ENABLED !== '') {
    return envFlag('CHAT_OUTBOX_ENABLED', false);
  }
  // Default: follow Discord→game relay flag so one switch enables both directions.
  return envFlag('CHAT_RELAY_ENABLED', false);
}

function outChannelId() {
  return (
    (process.env.CHAT_CHANNEL_ID || '').trim() ||
    (process.env.OUT_CHANNEL_ID || '').trim()
  );
}

function outboxPath(opts = {}) {
  const raw = (process.env.CHAT_OUTBOX_PATH || '').trim();
  if (raw) return path.resolve(raw);
  if (opts.chatRelayPath) {
    const dir = path.dirname(path.resolve(opts.chatRelayPath));
    return path.join(dir, 'chat_outbox.json');
  }
  const drop = (process.env.DROP_PATH || '').trim();
  if (drop) {
    return path.join(path.dirname(path.resolve(drop)), 'chat_outbox.json');
  }
  const relay = (process.env.CHAT_RELAY_PATH || '').trim();
  if (relay) {
    return path.join(path.dirname(path.resolve(relay)), 'chat_outbox.json');
  }
  return DEFAULT_OUTBOX;
}

function shouldSkip(entry) {
  if (!entry || typeof entry !== 'object') return true;
  const dir = String(entry.direction || 'out').toLowerCase();
  if (dir === 'in') return true;
  const src = String(entry.source || '').toLowerCase();
  if (src === 'discord') return true;
  if (entry.bot === true || entry.fromBot === true) return true;
  const content = String(entry.content || entry.text || '').trim();
  if (!content) return true;
  if (/^\[Discord\]/i.test(content)) return true;
  return false;
}

function formatLine(entry) {
  const author = String(entry.author || entry.user || 'Player').trim() || 'Player';
  let content = String(entry.content || entry.text || '').trim();
  if (content.length > MAX_CONTENT) {
    content = `${content.slice(0, MAX_CONTENT - 3)}...`;
  }
  return `**[In-game] ${author}:** ${content}`;
}

/**
 * @param {import('discord.js').Client} client
 * @param {{ chatRelayPath?: string }} [opts]
 */
function attachChatOutbox(client, opts = {}) {
  if (!isEnabled()) {
    console.log('[rfs-discord-bridge] chat outbox: disabled');
    return { stop() {} };
  }

  const filePath = outboxPath(opts);
  const channelId = outChannelId();
  if (!channelId) {
    console.warn(
      '[rfs-discord-bridge] chat outbox: enabled but CHAT_CHANNEL_ID / OUT_CHANNEL_ID unset — disabled'
    );
    return { stop() {} };
  }

  console.log(
    `[rfs-discord-bridge] chat outbox: poll ${filePath} → channel ${channelId}`
  );

  /** @type {string|null} */
  let lastId = null;
  let busy = false;
  let timer = null;

  async function tick() {
    if (busy) return;
    busy = true;
    try {
      if (!fs.existsSync(filePath)) return;

      let raw;
      try {
        raw = fs.readFileSync(filePath, 'utf8');
      } catch (_) {
        return;
      }

      let data;
      try {
        data = JSON.parse(raw);
      } catch (_) {
        return;
      }
      if (!data || typeof data !== 'object') return;

      const messages = Array.isArray(data.messages)
        ? data.messages
        : Array.isArray(data)
          ? data
          : [];
      if (messages.length === 0) return;

      // First see: seed cursor to end so we don't dump backlog into Discord.
      if (lastId === null) {
        for (let i = messages.length - 1; i >= 0; i--) {
          const id = String(messages[i]?.id || '');
          if (id) {
            lastId = id;
            break;
          }
        }
        if (lastId === null) lastId = '__seeded__';
        return;
      }

      let start = 0;
      if (lastId && lastId !== '__seeded__') {
        for (let i = 0; i < messages.length; i++) {
          if (String(messages[i]?.id || '') === lastId) {
            start = i + 1;
            break;
          }
        }
      }

      const channel = await client.channels.fetch(channelId).catch(() => null);
      if (!channel || typeof channel.send !== 'function') {
        console.warn(
          `[rfs-discord-bridge] chat outbox: channel ${channelId} not usable`
        );
        return;
      }

      for (let i = start; i < messages.length; i++) {
        const entry = messages[i];
        const id = String(entry?.id || '');
        if (!id || id === lastId) continue;
        if (shouldSkip(entry)) {
          lastId = id;
          continue;
        }
        await channel.send({ content: formatLine(entry) });
        lastId = id;
      }
    } catch (err) {
      console.warn('[rfs-discord-bridge] chat outbox tick failed:', err.message);
    } finally {
      busy = false;
    }
  }

  const startPoll = () => {
    if (timer) return;
    timer = setInterval(() => {
      tick().catch(() => {});
    }, POLL_MS);
    tick().catch(() => {});
  };

  if (client.isReady && client.isReady()) {
    startPoll();
  } else {
    client.once('ready', startPoll);
  }

  return {
    stop() {
      if (timer) {
        clearInterval(timer);
        timer = null;
      }
    },
    outboxPath: filePath,
    outChannelId: channelId,
  };
}

module.exports = {
  isEnabled,
  outChannelId,
  outboxPath,
  shouldSkip,
  formatLine,
  attachChatOutbox,
};
