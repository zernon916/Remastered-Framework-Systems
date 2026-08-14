/**
 * Vote permission locks for the RFS Discord bridge.
 *
 * Env (all optional):
 *   VOTE_CHANNEL_ID       — if set, /vote only allowed in this channel
 *   STREAMER_ROLE_ID      — if set and ALLOW_EVERYONE_VOTES is not true, require this role
 *   ALLOW_EVERYONE_VOTES  — true/1/yes → skip role check (default false)
 *
 * Channel lock always applies when VOTE_CHANNEL_ID is set.
 * Role lock applies only when STREAMER_ROLE_ID is set AND everyone-votes is off.
 * If everyone-votes is off and STREAMER_ROLE_ID is unset, votes are still allowed
 * (open server; only cooldown / allowlist apply).
 */

'use strict';

function envFlag(name, defaultValue = false) {
  const raw = process.env[name];
  if (raw === undefined || raw === null || String(raw).trim() === '') {
    return defaultValue;
  }
  const v = String(raw).trim().toLowerCase();
  if (['1', 'true', 'yes', 'on'].includes(v)) return true;
  if (['0', 'false', 'no', 'off'].includes(v)) return false;
  return defaultValue;
}

function memberHasRole(member, roleId) {
  if (!member || !roleId) return false;
  const roles = member.roles;
  if (!roles) return false;
  if (roles.cache && typeof roles.cache.has === 'function') {
    return roles.cache.has(roleId);
  }
  if (Array.isArray(roles)) {
    return roles.includes(roleId);
  }
  return false;
}

/**
 * Channel + role gates only (cooldown stays in index.js).
 * @param {import('discord.js').ChatInputCommandInteraction} interaction
 * @returns {{ ok: true } | { ok: false, reason: string }}
 */
function checkVotePermission(interaction) {
  const voteChannelId = (process.env.VOTE_CHANNEL_ID || '').trim();
  const streamerRoleId = (process.env.STREAMER_ROLE_ID || '').trim();
  const allowEveryone = envFlag('ALLOW_EVERYONE_VOTES', false);

  if (voteChannelId && interaction.channelId !== voteChannelId) {
    return {
      ok: false,
      reason: `Votes only allowed in channel <#${voteChannelId}>.`,
    };
  }

  if (!allowEveryone && streamerRoleId) {
    if (!memberHasRole(interaction.member, streamerRoleId)) {
      return {
        ok: false,
        reason: 'You need the streamer role to vote (or set ALLOW_EVERYONE_VOTES=true).',
      };
    }
  }

  return { ok: true };
}

function describeLocks() {
  return {
    voteChannelId: (process.env.VOTE_CHANNEL_ID || '').trim() || null,
    streamerRoleId: (process.env.STREAMER_ROLE_ID || '').trim() || null,
    allowEveryoneVotes: envFlag('ALLOW_EVERYONE_VOTES', false),
  };
}

module.exports = {
  checkVotePermission,
  describeLocks,
  envFlag,
};
