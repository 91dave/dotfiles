import assert from "node:assert/strict";
import test from "node:test";

import { resolve } from "node:path";

import {
  MERMAID,
  loadAssets,
  renderMdx,
  resolvePlanSource,
} from "./render.mjs";

const assets = await loadAssets();

const render = (body, frontmatter = "title: T") =>
  renderMdx(`---\n${frontmatter}\n---\n\n${body}\n`, assets);

const renderBody = async (source, frontmatter) => {
  const html = await render(source, frontmatter);
  return html.slice(html.indexOf("<main"), html.indexOf("</main>"));
};

const count = (haystack, needle) =>
  (haystack.match(new RegExp(needle, "g")) ?? []).length;

test("a .md plan file resolves as-is, so plan mode's harness file works", () => {
  assert.equal(
    resolvePlanSource("/home/dave/.claude/plans/playful-melody.md"),
    "/home/dave/.claude/plans/playful-melody.md",
  );
});

test("a .mdx plan file resolves as-is", () => {
  assert.equal(
    resolvePlanSource("/tmp/plans/thing/plan.mdx"),
    "/tmp/plans/thing/plan.mdx",
  );
});

test("a directory resolves to plan.mdx inside it", () => {
  assert.equal(
    resolvePlanSource("/tmp/repo/.plans/my-plan"),
    "/tmp/repo/.plans/my-plan/plan.mdx",
  );
});

test("an extensionless path is treated as a directory", () => {
  assert.equal(resolvePlanSource(".plans/my-plan"), resolve(".plans/my-plan/plan.mdx"));
});

test("a path whose directory merely contains a dot is not mistaken for a file", () => {
  assert.equal(
    resolvePlanSource("/tmp/repo/v1.2/my-plan"),
    "/tmp/repo/v1.2/my-plan/plan.mdx",
  );
});

test("frontmatter sets the title and work item chip", async () => {
  const html = await render("Body.", "title: Storage\nworkItem: AB#12345");
  assert.match(html, /<title>Storage<\/title>/);
  assert.match(html, /AB#12345/);
});

test("an AB# work item links to Azure DevOps", async () => {
  const html = await render("Body.", "title: Storage\nworkItem: AB#12345");
  assert.match(
    html,
    /<a class="vp-chip" href="https:\/\/dev\.azure\.com\/AMDigitalTech\/Technology\/_workitems\/edit\/12345">AB#12345<\/a>/,
  );
});

test("a work item that is not an AB# reference stays unlinked", async () => {
  const html = await render("Body.", "title: Storage\nworkItem: Spike");
  assert.match(html, /<span class="vp-chip">Spike<\/span>/);
});

const headerOf = (html) =>
  html.slice(html.indexOf('<header class="vp-head">'), html.indexOf("</header>"));

test("a leading markdown h1 becomes the page title and heading", async () => {
  const html = await render("# Storage Migration\n\nBody.", "brief: B");
  assert.match(html, /<title>Storage Migration<\/title>/);
  assert.match(headerOf(html), /<h1>Storage Migration<\/h1>/);
});

test("a leading h1 is lifted out of the body rather than repeated", async () => {
  const html = await render("# Storage Migration\n\nBody.", "brief: B");
  assert.equal(count(html, "Storage Migration</h1>"), 1);
});

test("a leading h1 wins over the frontmatter title", async () => {
  const html = await render("# From Heading\n\nBody.", "title: From Frontmatter");
  assert.match(headerOf(html), /<h1>From Heading<\/h1>/);
});

test("a leading h1 is found without any frontmatter", async () => {
  const html = await renderMdx("\n# Bare Heading\n\nBody.\n", assets);
  assert.match(headerOf(html), /<h1>Bare Heading<\/h1>/);
});

test("an h1 that is not the first content line is left in the body", async () => {
  const html = await render("Intro.\n\n# Later Heading", "title: Storage");
  assert.match(headerOf(html), /<h1>Storage<\/h1>/);
  assert.match(html, /<h1[^>]*>Later Heading<\/h1>/);
});

test("frontmatter tags render as chips in the header", async () => {
  const header = headerOf(await render("Body.", "title: T\ntags: [ 'plan', \"draft\", spike ]"));
  assert.match(header, /<span class="vp-chip vp-chip--muted">plan<\/span>/);
  assert.match(header, /<span class="vp-chip vp-chip--muted">draft<\/span>/);
  assert.match(header, /<span class="vp-chip vp-chip--muted">spike<\/span>/);
});

test("a single scalar tag renders as one chip", async () => {
  const header = headerOf(await render("Body.", "title: T\ntags: plan"));
  assert.equal(count(header, "vp-chip--muted"), 1);
});

test("no tags means no hardcoded Plan chip", async () => {
  const header = headerOf(await render("Body.", "title: T"));
  assert.doesNotMatch(header, /vp-chip--muted/);
});

test("the work item chip stays linked alongside tags", async () => {
  const header = headerOf(
    await render("Body.", "title: T\nworkItem: AB#12345\ntags: [ 'plan' ]"),
  );
  assert.match(header, /<a class="vp-chip" href="[^"]+\/12345">AB#12345<\/a>/);
  assert.match(header, />plan<\/span>/);
});

test("markdown renders as normal prose", async () => {
  const body = await renderBody("## Heading\n\nSome **bold** text.");
  assert.match(body, /<h2[^>]*>Heading<\/h2>/);
  assert.match(body, /<strong>bold<\/strong>/);
});

test("a fenced code block is highlighted and can carry a filename", async () => {
  const body = await renderBody("```csharp title=Resolver.cs\nvar x = 1;\n```");
  assert.match(body, /class="language-csharp"/);
  assert.match(body, /vp-code__title">Resolver\.cs</);
});

test("code content is escaped, not injected", async () => {
  const body = await renderBody(
    "```js\nconst evil = '<script>alert(1)</script>';\n```",
  );
  assert.match(body, /&lt;script&gt;alert\(1\)&lt;\/script&gt;/);
  assert.doesNotMatch(body, /<script>alert\(1\)<\/script>/);
});

test("mermaid fences emit the pinned CDN tag with integrity", async () => {
  const html = await render("```mermaid\nflowchart LR\n  A --> B\n```");
  assert.match(html, /<pre class="mermaid">flowchart LR/);
  assert.ok(html.includes(MERMAID.src));
  assert.ok(html.includes(MERMAID.integrity));
  assert.match(html, /crossorigin="anonymous"/);
});

test("a plan without diagrams loads nothing from the network", async () => {
  const html = await render("## Just prose\n\nNo diagrams here.");
  assert.doesNotMatch(html, /src="https?:\/\//);
  assert.doesNotMatch(html, /<link[^>]+href="https?:\/\//);
});

test("FileTree nests by path and shows change badges and notes", async () => {
  const body = await renderBody(
    '<FileTree entries={[{ path: "src/a/One.cs", change: "modified", note: "why" }, { path: "src/a/Two.cs", change: "added" }]} />',
  );
  assert.match(body, /vp-badge--modified">modified</);
  assert.match(body, /vp-tree__note">why</);
  assert.equal(count(body, "vp-tree__file"), 2);
  assert.equal(count(body, ">src/<"), 1);
  assert.equal(count(body, ">a/<"), 1);
});

test("Callout renders its children as markdown", async () => {
  const body = await renderBody(
    '<Callout tone="decision">\n\nUse the **existing** abstraction.\n\n</Callout>',
  );
  assert.match(body, /vp-callout--decision/);
  assert.match(body, /<strong>existing<\/strong>/);
});

test("an unknown Callout tone falls back to info", async () => {
  const body = await renderBody('<Callout tone="totally-made-up">Body</Callout>');
  assert.match(body, /vp-callout--info/);
  assert.doesNotMatch(body, /totally-made-up/);
});

test("Tasks renders ordered cards and derives the dependency graph", async () => {
  const body = await renderBody(
    '<Tasks items={[{ id: "a", title: "First", type: "Test" }, { id: "b", title: "Second", type: "Functional", dependsOn: ["a"] }]} />',
  );
  assert.match(body, /vp-badge--test">Test</);
  assert.match(body, /vp-badge--functional">Functional</);
  assert.match(body, /vp-task__deps">depends on <code>a<\/code>/);
  assert.match(body, /T1 --&gt; T2/);
  assert.equal(count(body, "vp-task__order"), 2);
});

test("a dependency on an unknown id is dropped from the graph", async () => {
  const body = await renderBody(
    '<Tasks items={[{ id: "a", title: "Only", type: "Test", dependsOn: ["ghost"] }]} />',
  );
  assert.doesNotMatch(body, /vp-tasks__graph/);
});

test("task fields render only when present", async () => {
  const body = await renderBody(
    '<Tasks items={[{ id: "a", title: "T", type: "Test", objective: "Do it", successCriteria: ["One", "Two"] }]} />',
  );
  assert.match(body, /<dt>Objective<\/dt>/);
  assert.match(body, /<li>One<\/li><li>Two<\/li>/);
  assert.doesNotMatch(body, /<dt>Inputs<\/dt>/);
});

test("malformed component data reports the component instead of rendering", async () => {
  const body = await renderBody("<Tasks items={[]} />");
  assert.match(body, /vp-error/);
  assert.match(body, /Tasks/);
});

test("an invalid attribute expression names the component and attribute", async () => {
  await assert.rejects(
    () => render("<Tasks items={[ this is not js } />"),
    /<Tasks> attribute "items"/,
  );
});

test("prose is not mistaken for a component tag", async () => {
  const body = await renderBody(
    "Use the `<Tasks>` block when there is a breakdown.",
  );
  assert.match(body, /&lt;Tasks&gt;/);
  assert.doesNotMatch(body, /<article class="vp-task"/);
});

test("several components in one document all render", async () => {
  const body = await renderBody(
    '<Callout tone="risk">Careful.</Callout>\n\nProse between.\n\n<FileTree entries={[{ path: "a.cs", change: "added" }]} />\n\n<Tasks items={[{ id: "x", title: "X", type: "Refactor" }]} />',
  );
  assert.equal(count(body, "vp-callout--risk"), 1);
  assert.equal(count(body, "vp-tree__file"), 1);
  assert.equal(count(body, "vp-task__order"), 1);
  assert.match(body, /Prose between\./);
});
