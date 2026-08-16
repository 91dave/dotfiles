import { createServer } from "node:http";
import { writeFile } from "node:fs/promises";
import { resolve } from "node:path";

import { loadAssets, renderFile, resolvePlanSource } from "./render.mjs";

const USAGE = `Usage:
  node lib/serve.mjs <plan-dir-or-file> [--port <n>]   serve and print a URL
  node lib/serve.mjs <plan-dir-or-file> --out <file>   write standalone HTML
`;

function parseArgs(argv) {
  const positional = [];
  const options = {};
  for (let i = 0; i < argv.length; i += 1) {
    if (argv[i] === "--port") options.port = Number(argv[++i]);
    else if (argv[i] === "--out") options.out = argv[++i];
    else if (argv[i] === "--help" || argv[i] === "-h") options.help = true;
    else positional.push(argv[i]);
  }
  return { target: positional[0], ...options };
}

const args = parseArgs(process.argv.slice(2));

if (args.help || !args.target) {
  process.stdout.write(USAGE);
  process.exit(args.target ? 0 : 1);
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

const server = createServer(async (req, res) => {
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

server.listen(args.port ?? 0, "127.0.0.1", () => {
  process.stdout.write(`http://127.0.0.1:${server.address().port}\n`);
  process.stdout.write(`serving ${source}\n`);
  process.stdout.write("edit the mdx and reload; ctrl-c to stop\n");
});
