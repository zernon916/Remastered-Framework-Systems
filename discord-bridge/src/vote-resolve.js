/**
 * Vote resolve — game → Discord (Phase C).
 *
 * RfsStreamer.lua writes vote_result.json after apply / permanent reject.
 * This module polls that file and announces once per id.
 *
 * Env:
 *   RESULT_CHANNEL_ID  — optional; falls back to VOTE_CHANNEL_ID
 *   RESULT_PATH        — optional absolute path to vote_result.json
 *                        (default: same folder as DROP_PATH / inbox/vote_result.json)
 */

'use strict';

const fs = require('fs');
const path = require('path');

const DEFAULT_VOTE = path.join(__dirname, '..', 'inbox', 'vote.json');
const POLL_MS = 1000;

function resultChannelId() {
  return (
    (process.env.RESULT_CHANNEL_ID || '').trim() ||
    (process.env.VOTE_CHANNEL_ID || '').trim()
  );
}

/**
 * Resolve poll path. Prefer RESULT_PATH; else sibling of DROP_PATH / default vote.
 * @param {string} [voteDropPath]
 */
function resultDropPath(voteDropPath) {
  const raw = (process.env.RESULT_PATH || '').trim();
  if (raw) return path.resolve(raw);
  const votePath = voteDropPath
    ? path.resolve(voteDropPath)
    : (process.env.DROP_PATH || '').trim()
      ? path.resolve(process.env.DROP_PATH)
      : DEFAULT_VOTE;
  return path.join(path.dirname(votePath), 'vote_result.json');
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

function formatAnnounce(data) {
  const ok = data.ok === true;
  if (ok) {
    const detail = String(data.detail || 'applied').trim() || 'applied';
    return `✅ Streamer: ${detail}`;
  }
  const reason = String(data.error || data.detail || 'rejected').trim() || 'rejected';
  return `❌ Streamer: ${reason}`;
}

/**
 * @param {import('discord.js').Client} client
 * @param {{ voteDropPath?: string }} [opts]
 */
function attachVoteResolve(client, opts = {}) {
  const filePath = resultDropPath(opts.voteDropPath);
  const channelId = resultChannelId();

  if (!channelId) {
    console.warn(
      '[rfs-discord-bridge] vote resolve: no RESULT_CHANNEL_ID / VOTE_CHANNEL_ID — disabled'
    );
    return { stop() {} };
  }

  console.log(
    `[rfs-discord-bridge] vote resolve: poll ${filePath} → channel ${channelId}`
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
      if (data.consumed === true) return;

      const id = String(data.id || data.ts || '');
      if (!id || id === lastId) return;

      const channel = await client.channels.fetch(channelId).catch(() => null);
      if (!channel || typeof channel.send !== 'function') {
        console.warn(
          `[rfs-discord-bridge] vote resolve: channel ${channelId} not usable`
        );
        return;
      }

      await channel.send({ content: formatAnnounce(data) });
      lastId = id;

      const marked = Object.assign({}, data, {
        consumed: true,
        announcedAt: new Date().toISOString(),
      });
      try {
        atomicWriteJson(filePath, marked);
      } catch (err) {
        console.warn(
          '[rfs-discord-bridge] vote resolve: mark consumed failed:',
          err.message
        );
      }
    } catch (err) {
      console.warn('[rfs-discord-bridge] vote resolve tick failed:', err.message);
    } finally {
      busy = false;
    }
  }

  const start = () => {
    if (timer) return;
    timer = setInterval(() => {
      tick().catch(() => {});
    }, POLL_MS);
    tick().catch(() => {});
  };

  if (client.isReady && client.isReady()) {
    start();
  } else {
    client.once('ready', start);
  }

  return {
    stop() {
      if (timer) {
        clearInterval(timer);
        timer = null;
      }
    },
    resultDropPath: filePath,
    resultChannelId: channelId,
  };
}

module.exports = {
  resultChannelId,
  resultDropPath,
  formatAnnounce,
  attachVoteResolve,
};
