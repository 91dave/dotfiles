import { createServer } from "node:http";
import { writeFile } from "node:fs/promises";
import { resolve } from "node:path";

import { loadAssets, renderFile, resolvePlanSource } from "./render.mjs";

const DEFAULT_PORT = 7842;
const DEFAULT_IDLE_MINUTES = 30;

const USAGE = `Usage:
  node lib/serve.mjs <plan-dir-or-file> [--port <n>] [--idle <minutes>]
  node lib/serve.mjs <plan-dir-or-file> --out <file>   write standalone HTML

Serves on ${DEFAULT_PORT}, falling back to a free port if that is taken.
Exits after ${DEFAULT_IDLE_MINUTES} minutes with no requests; --idle 0 disables that.
`;

function parseArgs(argv) {
  const positional = [];
  const options = {};
  for (let i = 0; i < argv.length; i += 1) {
    if (argv[i] === "--port") options.port = Number(argv[++i]);
    else if (argv[i] === "--idle") options.idle = Number(argv[++i]);
    else if (argv[i] === "--out") options.out = argv[++i];
    else if (argv[i] === "--help" || argv[i] === "-h") options.help = true;
    else positional.push(argv[i]);
  }
  return { target: positional[0], ...options };
}

const args = parseArgs(process.argv.slice(2));

if (args.help || !args.target) {
  process.stdout.write(USAGE);
  process.exit(args.help ? 0 : 1);
}

const source = resolvePlanSource(args.target);
const assets = await loadAssets();

if (args.out) {
  try {
    await writeFile(resolve(args.out), await renderFile(source, assets), "utf8");
  } catch (error) {
    process.stderr.write(`${source}\n${error.message}\n`);
    process.exit(1);
  }
  process.stdout.write(`${resolve(args.out)}\n`);
  process.exit(0);
}

const idleMs = (args.idle ?? DEFAULT_IDLE_MINUTES) * 60_000;
let idleTimer;

function restartIdleCountdown() {
  if (!idleMs) return;
  clearTimeout(idleTimer);
  idleTimer = setTimeout(() => {
    process.stdout.write(`no requests for ${idleMs / 60_000} minutes, stopping\n`);
    server.close(() => process.exit(0));
  }, idleMs);
}

const server = createServer(async (req, res) => {
  restartIdleCountdown();
  if (req.method !== "GET") {
    res.writeHead(405, { allow: "GET" }).end("Method not allowed");
    return;
  }
  try {
    const html = await renderFile(source, assets);
    res.writeHead(200, {
      "content-type": "text/html; charset=utf-8",
      "cache-control": "no-store",
    });
    res.end(html);
  } catch (error) {
    res.writeHead(500, { "content-type": "text/plain; charset=utf-8" });
    res.end(`Render failed:\n\n${error.stack ?? error.message}`);
  }
});

const requestedPort = args.port ?? DEFAULT_PORT;
let usingFallbackPort = false;

server.on("error", (error) => {
  if (error.code === "EADDRINUSE" && !usingFallbackPort) {
    usingFallbackPort = true;
    process.stderr.write(
      `port ${requestedPort} is in use, probably by another plan still being served; using a free port instead\n`,
    );
    server.listen(0, "127.0.0.1");
    return;
  }
  process.stderr.write(`${error.message}\n`);
  process.exit(1);
});

server.on("listening", () => {
  process.stdout.write(`http://127.0.0.1:${server.address().port}\n`);
  process.stdout.write(`serving ${source}\n`);
  const stops = idleMs
    ? `stops after ${idleMs / 60_000} minutes idle`
    : "runs until stopped";
  process.stdout.write(`edit the plan and reload; ${stops}; ctrl-c to stop\n`);
  restartIdleCountdown();
});

server.listen(requestedPort, "127.0.0.1");
