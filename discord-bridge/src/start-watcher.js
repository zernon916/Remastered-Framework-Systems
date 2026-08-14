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
 *   DROP_PATH               If set, also watch that file's directory
 *   RFS_BRIDGE_POLL_MS      Poll interval (default 1000)
 *
 * Default USER_DATA scan roots (when RFS_BRIDGE_REQUEST_DIR unset):
 *   Windows: %APPDATA%/Axolot Games/Scrap Mechanic/User/User_<id>/rfs_discord_bridge
 *   Linux:   ~/.local/share/.../User_<id> and common Steam/Proton prefixes (app 387990)
 *   macOS:   ~/Library/Application Support/.../User_<id> (SM rarely runs on Mac;
 *            prefer RFS_BRIDGE_REQUEST_DIR or run the bot on the SM host)
 */
"use strict";

const fs = require("fs");
const os = require("os");
const path = require("path");
const { spawn } = require("child_process");

const ROOT = path.resolve(__dirname, "..");
const BOT_ENTRY = path.join(ROOT, "src", "index.js");
const POLL_MS = Math.max(250, Number(process.env.RFS_BRIDGE_POLL_MS) || 1000);
const REQUEST_DIR_OVERRIDE = process.env.RFS_BRIDGE_REQUEST_DIR
  ? path.resolve(process.env.RFS_BRIDGE_REQUEST_DIR)
  : null;
/** Scrap Mechanic Steam app id (Proton compatdata). */
const SM_STEAM_APPID = "387990";

let botChild = null;
const lastHandled = Object.create(null); // key: absPath -> last id/mtime signature

function log(...args) {
  console.log("[rfs-start-watcher]", ...args);
}

/**
 * Push unique absolute paths onto `out`.
 * @param {string[]} out
 * @param {Set<string>} seen
 * @param {string} dir
 */
function pushUnique(out, seen, dir) {
  const abs = path.resolve(dir);
  if (seen.has(abs)) return;
  seen.add(abs);
  out.push(abs);
}

/**
 * Expand a Scrap Mechanic `User` root into User_<id>/rfs_discord_bridge dirs.
 * @param {string} usersRoot
 * @param {string[]} out
 * @param {Set<string>} seen
 */
function collectUserBridgeDirs(usersRoot, out, seen) {
  if (!usersRoot || !fs.existsSync(usersRoot)) return;
  let names;
  try {
    names = fs.readdirSync(usersRoot);
  } catch {
    return;
  }
  for (const name of names) {
    if (!name.startsWith("User_")) continue;
    pushUnique(out, seen, path.join(usersRoot, name, "rfs_discord_bridge"));
  }
}

/**
 * Common Steam library roots on Linux (native + Flatpak).
 * @param {string} home
 * @returns {string[]}
 */
function linuxSteamRoots(home) {
  return [
    path.join(home, ".steam", "steam"),
    path.join(home, ".steam", "root"),
    path.join(home, ".local", "share", "Steam"),
    path.join(home, ".var", "app", "com.valvesoftware.Steam", ".local", "share", "Steam"),
  ];
}

/**
 * Proton USER_DATA under a Steam library (Windows-style AppData inside the prefix).
 * @param {string} steamRoot
 * @returns {string[]}
 */
function protonSmUserRoots(steamRoot) {
  const compat = path.join(steamRoot, "steamapps", "compatdata", SM_STEAM_APPID);
  const pfxUsers = path.join(compat, "pfx", "drive_c", "users");
  if (!fs.existsSync(pfxUsers)) return [];
  const roots = [];
  let userNames;
  try {
    userNames = fs.readdirSync(pfxUsers);
  } catch {
    return [];
  }
  for (const u of userNames) {
    roots.push(
      path.join(
        pfxUsers,
        u,
        "AppData",
        "Roaming",
        "Axolot Games",
        "Scrap Mechanic",
        "User"
      )
    );
  }
  return roots;
}

/**
 * Candidate Scrap Mechanic `User` directories for this OS (before User_* expand).
 * @returns {string[]}
 */
function defaultSmUserRoots() {
  const home = os.homedir();
  const roots = [];

  if (process.platform === "win32") {
    const appData =
      process.env.APPDATA || path.join(home, "AppData", "Roaming");
    roots.push(path.join(appData, "Axolot Games", "Scrap Mechanic", "User"));
    return roots;
  }

  if (process.platform === "darwin") {
    roots.push(
      path.join(
        home,
        "Library",
        "Application Support",
        "Axolot Games",
        "Scrap Mechanic",
        "User"
      )
    );
    return roots;
  }

  // Linux: native path + Proton/Wine prefixes under common Steam libs
  roots.push(
    path.join(home, ".local", "share", "Axolot Games", "Scrap Mechanic", "User")
  );
  for (const steam of linuxSteamRoots(home)) {
    if (!fs.existsSync(steam)) continue;
    for (const r of protonSmUserRoots(steam)) {
      roots.push(r);
    }
  }
  return roots;
}

/**
 * Directories that may contain start_request.json / stop_request.json.
 * Prefer RFS_BRIDGE_REQUEST_DIR, then DROP_PATH's folder, then OS User_* scan.
 * @returns {string[]}
 */
function smUserRoots() {
  const out = [];
  const seen = new Set();

  if (REQUEST_DIR_OVERRIDE) {
    pushUnique(out, seen, REQUEST_DIR_OVERRIDE);
    return out;
  }

  const drop = (process.env.DROP_PATH || "").trim();
  if (drop) {
    pushUnique(out, seen, path.dirname(path.resolve(drop)));
  }

  for (const usersRoot of defaultSmUserRoots()) {
    collectUserBridgeDirs(usersRoot, out, seen);
  }
  return out;
}

function describeScanRoots() {
  if (REQUEST_DIR_OVERRIDE) {
    return `RFS_BRIDGE_REQUEST_DIR=${REQUEST_DIR_OVERRIDE}`;
  }
  const parts = [`platform=${process.platform}`];
  if ((process.env.DROP_PATH || "").trim()) {
    parts.push("also watching dirname(DROP_PATH)");
  }
  if (process.platform === "win32") {
    parts.push(
      "%APPDATA%/Axolot Games/Scrap Mechanic/User/User_<id>/rfs_discord_bridge"
    );
  } else if (process.platform === "darwin") {
    parts.push(
      "~/Library/Application Support/Axolot Games/Scrap Mechanic/User/User_<id>/rfs_discord_bridge"
    );
  } else {
    parts.push(
      "~/.local/share/Axolot Games/Scrap Mechanic/User/User_<id>/rfs_discord_bridge"
    );
    parts.push(
      "Steam Proton compatdata/" +
        SM_STEAM_APPID +
        "/.../Scrap Mechanic/User/User_<id>/rfs_discord_bridge"
    );
  }
  return parts.join("; ");
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
  // Cross-platform: same Node binary, no shell, no cmd/start /B
  botChild = spawn(process.execPath, [BOT_ENTRY], {
    cwd: ROOT,
    env: process.env,
    stdio: "inherit",
    shell: false,
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
  // Force-kill after grace if still alive (Node maps SIGKILL on all platforms)
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
  const filePath = path.join(
    dir,
    action === "start" ? "start_request.json" : "stop_request.json"
  );
  if (!fs.existsSync(filePath)) return;
  const data = readJson(filePath);
  const sig = signature(filePath, data);
  const key = filePath;
  if (lastHandled[key] === sig) {
    // Already handled this payload; leave file until game overwrites (or consume stale)
    return;
  }
  lastHandled[key] = sig;
  log(
    "saw",
    action,
    "request at",
    filePath,
    data && data.id ? `(id ${data.id})` : ""
  );
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
  log("scan:", describeScanRoots());
  log("bot entry:", BOT_ENTRY);
  log("in-game: /gensettings → DISCORD → Start/Stop Discord bot");
  tick();
  setInterval(tick, POLL_MS);
}

main();
