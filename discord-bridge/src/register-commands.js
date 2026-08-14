/**
 * Deploy slash commands to the Discord guild (or globally if GUILD_ID unset).
 * Usage: npm run register
 */

'use strict';

const path = require('path');
require('dotenv').config({ path: path.join(__dirname, '..', '.env') });

const { REST, Routes, SlashCommandBuilder } = require('discord.js');

const TOKEN = process.env.DISCORD_TOKEN || '';
const CLIENT_ID = process.env.CLIENT_ID || process.env.DISCORD_CLIENT_ID || '';
const GUILD_ID = process.env.GUILD_ID || process.env.DISCORD_GUILD_ID || '';

function buildCommands() {
  return [
    new SlashCommandBuilder()
      .setName('ping')
      .setDescription('Health check for the RFS Discord bridge'),
    new SlashCommandBuilder()
      .setName('vote')
      .setDescription('Cast a Streamer-mode vote (spawn unit or give item)')
      .addStringOption((opt) =>
        opt
          .setName('action')
          .setDescription('spawn a unit or give an item')
          .setRequired(true)
          .addChoices(
            { name: 'spawn', value: 'spawn' },
            { name: 'give', value: 'give' }
          )
      )
      .addStringOption((opt) =>
        opt
          .setName('unit')
          .setDescription('Unit alias for spawn (e.g. farmbot, haybot)')
          .setRequired(false)
      )
      .addStringOption((opt) =>
        opt
          .setName('item')
          .setDescription('Item alias or UUID for give (see config/allowlist.json)')
          .setRequired(false)
      )
      .addIntegerOption((opt) =>
        opt
          .setName('amount')
          .setDescription('How many units / items (1–20)')
          .setRequired(false)
          .setMinValue(1)
          .setMaxValue(20)
      ),
  ].map((c) => c.toJSON());
}

async function registerCommands() {
  if (!TOKEN || !CLIENT_ID) {
    console.error('DISCORD_TOKEN and CLIENT_ID (or DISCORD_CLIENT_ID) are required.');
    process.exit(1);
  }

  const rest = new REST({ version: '10' }).setToken(TOKEN);
  const body = buildCommands();

  if (GUILD_ID) {
    await rest.put(Routes.applicationGuildCommands(CLIENT_ID, GUILD_ID), { body });
    console.log(`[rfs-discord-bridge] Registered guild commands on ${GUILD_ID}`);
  } else {
    await rest.put(Routes.applicationCommands(CLIENT_ID), { body });
    console.log(
      '[rfs-discord-bridge] Registered global application commands (may take up to ~1h).'
    );
  }
}

module.exports = { buildCommands, registerCommands };

if (require.main === module) {
  registerCommands().catch((err) => {
    console.error(err);
    process.exit(1);
  });
}
