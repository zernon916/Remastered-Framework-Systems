/**
 * Poll Scrap Mechanic USER_DATA for GenSettings Discord start/stop requests.
 * Lua cannot spawn Node; /gensettings → Discord tab writes:
 *   $USER_DATA/rfs_discord_bridge/start_request.json
 *   $USER_DATA/rfs_discord_bridge/stop_request.json
 * This process watches those files and spawns/stops `node src/index.js`.
 *
 * Usage (from discord-bridge/): npm run watch
 *
 * Env:
 *   RFS_BRIDGE_REQUEST_DIR  Absolute path to rfs_discord_bridge (skip User_* scan)
 *   RFS_BRIDGE_POLL_MS      Poll interval (default 1000)
 */
"use strict";

const fs = require("fs");
const path = require("path");
const { spawn } = require("child_process");

const ROOT = path.resolve(__dirname, "..");
const BOT_ENTRY = path.join(ROOT, "src", "index.js");
const POLL_MS = Math.max(250, Number(process.env.RFS_BRIDGE_POLL_MS) || 1000);
const REQUEST_DIR_OVERRIDE = process.env.RFS_BRIDGE_REQUEST_DIR
  ? path.resolve(process.env.RFS_BRIDGE_REQUEST_DIR)
  : null;

let botChild = null;
const lastHandled = Object.create(null); // key: absPath -> last id/mtime signature

function log(...args) {
  console.log("[rfs-start-watcher]", ...args);
}

function smUserRoots() {
  if (REQUEST_DIR_OVERRIDE) {
    return [REQUEST_DIR_OVERRIDE];
  }
  const appData = process.env.APPDATA || "";
  if (!appData) return [];
  const usersRoot = path.join(appData, "Axolot Games", "Scrap Mechanic", "User");
  if (!fs.existsSync(usersRoot)) return [];
  const out = [];
  for (const name of fs.readdirSync(usersRoot)) {
    if (!name.startsWith("User_")) continue;
    out.push(path.join(usersRoot, name, "rfs_discord_bridge"));
  }
  return out;
}

function readJson(filePath) {
  try {
    const raw = fs.readFileSync(filePath, "utf8");
    return JSON.parse(raw);
  } catch {
    return null;
  }
}

function consume(filePath) {
  try {
    fs.unlinkSync(filePath);
  } catch {
    /* ignore */
  }
}

function signature(filePath, data) {
  if (data && data.id != null) return String(data.id);
  try {
    const st = fs.statSync(filePath);
    return `${st.mtimeMs}:${st.size}`;
  } catch {
    return String(Date.now());
  }
}

function isBotRunning() {
  return !!(botChild && botChild.exitCode === null && !botChild.killed);
}

function startBot() {
  if (isBotRunning()) {
    log("bot already running (pid", botChild.pid + ")");
    return;
  }
  if (!fs.existsSync(BOT_ENTRY)) {
    log("missing bot entry:", BOT_ENTRY);
    return;
  }
  log("starting bot:", BOT_ENTRY);
  botChild = spawn(process.execPath, [BOT_ENTRY], {
    cwd: ROOT,
    env: process.env,
    stdio: "inherit",
    windowsHide: true,
  });
  botChild.on("exit", (code, signal) => {
    log("bot exited code=", code, "signal=", signal);
    botChild = null;
  });
  botChild.on("error", (err) => {
    log("bot spawn error:", err.message);
    botChild = null;
  });
}

function stopBot() {
  if (!isBotRunning()) {
    log("stop requested but bot is not running");
    return;
  }
  const child = botChild;
  log("stopping bot (pid", child.pid + ")");
  try {
    child.kill("SIGTERM");
  } catch (err) {
    log("kill failed:", err.message);
  }
  // Windows fallback: force-kill after a short grace if still alive
  setTimeout(() => {
    if (botChild === child && isBotRunning()) {
      try {
        child.kill("SIGKILL");
      } catch {
        /* ignore */
      }
    }
  }, 3000);
}

function handleRequest(dir, action) {
  const filePath = path.join(dir, action === "start" ? "start_request.json" : "stop_request.json");
  if (!fs.existsSync(filePath)) return;
  const data = readJson(filePath);
  const sig = signature(filePath, data);
  const key = filePath;
  if (lastHandled[key] === sig) {
    // Already handled this payload; leave file until game overwrites (or consume stale)
    return;
  }
  lastHandled[key] = sig;
  log("saw", action, "request at", filePath, data && data.id ? `(id ${data.id})` : "");
  if (action === "start") startBot();
  else stopBot();
  consume(filePath);
}

function tick() {
  const dirs = smUserRoots();
  if (dirs.length === 0) return;
  for (const dir of dirs) {
    try {
      if (!fs.existsSync(dir)) continue;
    } catch {
      continue;
    }
    handleRequest(dir, "stop");
    handleRequest(dir, "start");
  }
}

function main() {
  log("polling every", POLL_MS, "ms");
  if (REQUEST_DIR_OVERRIDE) {
    log("REQUEST_DIR override:", REQUEST_DIR_OVERRIDE);
  } else {
    log("scanning %APPDATA%\\\\Axolot Games\\\\Scrap Mechanic\\\\User\\\\User_*\\\\rfs_discord_bridge");
  }
  log("bot entry:", BOT_ENTRY);
  log("in-game: /gensettings → DISCORD → Start/Stop Discord bot");
  tick();
  setInterval(tick, POLL_MS);
}

main();
