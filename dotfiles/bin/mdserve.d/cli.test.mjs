import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdtempSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";

const CLI = join(dirname(fileURLToPath(import.meta.url)), "cli.mjs");

const run = (...args) =>
  spawnSync(process.execPath, [CLI, ...args], { encoding: "utf8" });

function planDirectory() {
  const dir = mkdtempSync(join(tmpdir(), "mdserve-"));
  writeFileSync(join(dir, "plan.mdx"), "---\ntitle: Sample plan\n---\n\nBody.\n");
  return dir;
}

test("--help prints usage and succeeds", () => {
  const result = run("--help");
  assert.equal(result.status, 0);
  assert.match(result.stdout, /mdserve serve <plan>/);
});

test("no command prints usage to stderr and fails", () => {
  const result = run();
  assert.equal(result.status, 2);
  assert.match(result.stderr, /Usage:/);
});

test("render without --out writes html to stdout", () => {
  const result = run("render", planDirectory());
  assert.equal(result.status, 0);
  assert.match(result.stdout, /<title>Sample plan<\/title>/);
});

test("render --out writes the file and prints its path", () => {
  const dir = planDirectory();
  const out = join(dir, "plan.html");
  const result = run("render", dir, "--out", out);
  assert.equal(result.status, 0);
  assert.equal(result.stdout.trim(), out);
  assert.match(readFileSync(out, "utf8"), /<title>Sample plan<\/title>/);
});

test("render of a missing plan fails with the path", () => {
  const result = run("render", join(tmpdir(), "no-such-plan"));
  assert.equal(result.status, 1);
  assert.match(result.stderr, /no-such-plan/);
});
