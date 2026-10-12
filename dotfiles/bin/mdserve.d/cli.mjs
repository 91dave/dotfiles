import { spawnSync } from "node:child_process";
import { createServer } from "node:http";
import { writeFile } from "node:fs/promises";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

import { loadAssets, renderFile, resolvePlanSource } from "./render.mjs";

const HERE = dirname(fileURLToPath(import.meta.url));
const DEFAULT_PORT = 7842;
const DEFAULT_IDLE_MINUTES = 30;

const USAGE = `mdserve - render an MDX plan document and serve it for browser review

Usage:
  mdserve serve <plan> [--port <n>] [--idle <minutes>]
  mdserve render <plan> [--out <file>]
  mdserve test
  mdserve --help

<plan> is a .md or .mdx file, or a directory containing plan.mdx.

serve   Render on every request and serve on 127.0.0.1:${DEFAULT_PORT}, falling
        back to a free port if that is taken. Stops after ${DEFAULT_IDLE_MINUTES} idle
        minutes; --idle 0 runs until stopped. Only reads.
render  Write standalone HTML to --out, or to stdout without it.
test    Run the renderer's self-check.
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
  const [command, target] = positional;
  return { command, target, ...options };
}

function fail(message) {
  process.stderr.write(`${message}\n`);
  process.exit(1);
}

async function render({ target, out }) {
  const source = resolvePlanSource(target);
  let html;
  try {
    html = await renderFile(source, await loadAssets());
  } catch (error) {
    fail(`${source}\n${error.message}`);
  }
  if (!out) {
    process.stdout.write(html);
    return;
  }
  await writeFile(resolve(out), html, "utf8");
  process.stdout.write(`${resolve(out)}\n`);
}

async function serve({ target, port, idle }) {
  const source = resolvePlanSource(target);
  const assets = await loadAssets();
  const idleMs = (idle ?? DEFAULT_IDLE_MINUTES) * 60_000;
  let idleTimer;

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

  function restartIdleCountdown() {
    if (!idleMs) return;
    clearTimeout(idleTimer);
    idleTimer = setTimeout(() => {
      process.stdout.write(`no requests for ${idleMs / 60_000} minutes, stopping\n`);
      server.close(() => process.exit(0));
    }, idleMs);
  }

  const requestedPort = port ?? DEFAULT_PORT;
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
    fail(error.message);
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
}

function selfTest() {
  const result = spawnSync(
    process.execPath,
    ["--test", join(HERE, "render.test.mjs"), join(HERE, "cli.test.mjs")],
    { stdio: "inherit" },
  );
  process.exit(result.status ?? 1);
}

const args = parseArgs(process.argv.slice(2));

if (args.help) {
  process.stdout.write(USAGE);
} else if (args.command === "test") {
  selfTest();
} else if (args.command === "serve" && args.target) {
  await serve(args);
} else if (args.command === "render" && args.target) {
  await render(args);
} else {
  process.stderr.write(USAGE);
  process.exit(2);
}
