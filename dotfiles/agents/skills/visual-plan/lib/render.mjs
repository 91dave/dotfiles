import { readFile } from "node:fs/promises";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

import { Marked } from "../assets/marked.esm.js";
import {
  PAIRED,
  components,
  escapeHtml,
  mermaidWithSourceFallback,
} from "./components.mjs";

const HERE = dirname(fileURLToPath(import.meta.url));
const ASSETS = join(HERE, "..", "assets");

export const MERMAID = {
  version: "11.16.1",
  src: "https://cdn.jsdelivr.net/npm/mermaid@11.16.1/dist/mermaid.min.js",
  integrity:
    "sha384-aBQXj4hK6Jm05i7aQAsUV3bLdSUrHX1BGYfMB0166TtWt/RRaw+h0Eelme9OCOvy",
};

const placeholderToken = (index) => `vpblockmarker${index}end`;

export function resolvePlanSource(target) {
  return /\.mdx?$/.test(target)
    ? resolve(target)
    : resolve(target, "plan.mdx");
}

export async function loadAssets() {
  const [highlightJs, lightCss, darkCss, planCss] = await Promise.all([
    readFile(join(ASSETS, "highlight.min.js"), "utf8"),
    readFile(join(ASSETS, "highlight-light.css"), "utf8"),
    readFile(join(ASSETS, "highlight-dark.css"), "utf8"),
    readFile(join(HERE, "plan.css"), "utf8"),
  ]);
  return { highlightJs, lightCss, darkCss, planCss };
}

function splitFrontmatter(source) {
  const match = source.match(/^---\r?\n([\s\S]*?)\r?\n---\r?\n?/);
  if (!match) return { meta: {}, body: source };

  const meta = {};
  for (const line of match[1].split(/\r?\n/)) {
    const pair = line.match(/^([A-Za-z][\w-]*):\s*(.*)$/);
    if (pair) meta[pair[1]] = pair[2].trim().replace(/^["']|["']$/g, "");
  }
  return { meta, body: source.slice(match[0].length) };
}

function evaluateAttributes(raw, componentName) {
  const attributes = {};
  const pattern = /([A-Za-z][\w-]*)\s*=\s*(\{|")/g;

  let match;
  while ((match = pattern.exec(raw)) !== null) {
    const [, name, opener] = match;
    const valueStart = match.index + match[0].length;

    if (opener === '"') {
      const end = raw.indexOf('"', valueStart);
      if (end === -1) break;
      attributes[name] = raw.slice(valueStart, end);
      pattern.lastIndex = end + 1;
      continue;
    }

    let depth = 1;
    let cursor = valueStart;
    while (cursor < raw.length && depth > 0) {
      if (raw[cursor] === "{") depth += 1;
      else if (raw[cursor] === "}") depth -= 1;
      cursor += 1;
    }
    const expression = raw.slice(valueStart, cursor - 1);
    try {
      attributes[name] = new Function(`return (${expression})`)();
    } catch (error) {
      throw new Error(
        `<${componentName}> attribute "${name}" is not a valid expression: ${error.message}\n  ${expression.trim().slice(0, 200)}`,
      );
    }
    pattern.lastIndex = cursor;
  }
  return attributes;
}

function extractComponents(body) {
  const placeholders = [];
  const pattern = new RegExp(
    `^<(${Object.keys(components).join("|")})([\\s\\S]*?)(/>|>)`,
    "m",
  );

  let working = body;
  let match;
  while ((match = pattern.exec(working)) !== null) {
    const [opening, name, rawAttributes, terminator] = match;
    const start = match.index;
    let end = start + opening.length;
    let children = "";

    if (terminator === ">" && PAIRED.has(name)) {
      const closing = `</${name}>`;
      const closeAt = working.indexOf(closing, end);
      if (closeAt === -1) break;
      children = working.slice(end, closeAt);
      end = closeAt + closing.length;
    }

    const token = placeholderToken(placeholders.length);
    placeholders.push({
      name,
      attributes: evaluateAttributes(rawAttributes, name),
      children,
    });
    working = `${working.slice(0, start)}\n\n${token}\n\n${working.slice(end)}`;
  }
  return { body: working, placeholders };
}

function createMarked(usesMermaid) {
  const marked = new Marked({ gfm: true });
  marked.use({
    renderer: {
      code({ text, lang }) {
        const info = lang ?? "";
        const language = info.split(/\s+/)[0];
        if (language === "mermaid") {
          usesMermaid.value = true;
          return mermaidWithSourceFallback(text);
        }
        const title = info.match(/title=(?:"([^"]*)"|(\S+))/);
        const header = title
          ? `<div class="vp-code__title">${escapeHtml(title[1] ?? title[2])}</div>`
          : "";
        const cls = language ? ` class="language-${escapeHtml(language)}"` : "";
        return `<figure class="vp-code">${header}<pre><code${cls}>${escapeHtml(text)}</code></pre></figure>`;
      },
    },
  });
  return marked;
}

export async function renderMdx(source, assets) {
  const { meta, body } = splitFrontmatter(source);
  const usesMermaid = { value: false };
  const marked = createMarked(usesMermaid);

  const extracted = extractComponents(body);
  let html = await marked.parse(extracted.body);

  for (const [index, placeholder] of extracted.placeholders.entries()) {
    const { name, attributes, children } = placeholder;
    const rendered = components[name](
      attributes,
      children ? await marked.parse(children) : "",
    );
    const token = placeholderToken(index);
    html = html.replace(
      new RegExp(`<p>\\s*${token}\\s*</p>|${token}`),
      () => rendered,
    );
  }

  return wrapDocument({ meta, html, assets, usesMermaid: usesMermaid.value });
}

const AZDO_WORK_ITEM_URL =
  "https://dev.azure.com/AMDigitalTech/Technology/_workitems/edit/";

function workItemChip(workItem) {
  const label = escapeHtml(workItem);
  const id = /^AB#(\d+)$/i.exec(workItem.trim())?.[1];
  return id
    ? `<a class="vp-chip" href="${AZDO_WORK_ITEM_URL}${id}">${label}</a>`
    : `<span class="vp-chip">${label}</span>`;
}

function wrapDocument({ meta, html, assets, usesMermaid }) {
  const title = meta.title ?? "Plan";
  const brief = meta.brief
    ? `<p class="vp-brief">${escapeHtml(meta.brief)}</p>`
    : "";
  const item = meta.workItem ? workItemChip(meta.workItem) : "";

  const mermaidTag = usesMermaid
    ? `<script src="${MERMAID.src}" integrity="${MERMAID.integrity}" crossorigin="anonymous"></script>
<script>
  if (window.mermaid) {
    var dark = matchMedia("(prefers-color-scheme: dark)").matches;
    mermaid.initialize({ startOnLoad: true, theme: dark ? "dark" : "neutral" });
  }
</script>`
    : "";

  return `<!doctype html>
<html lang="en-GB">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${escapeHtml(title)}</title>
<style>
${assets.planCss}
@media (prefers-color-scheme: light) { ${assets.lightCss} }
@media (prefers-color-scheme: dark) { ${assets.darkCss} }
</style>
</head>
<body>
<main class="vp-doc">
<header class="vp-head">
<div class="vp-head__meta">${item}<span class="vp-chip vp-chip--muted">Plan</span></div>
<h1>${escapeHtml(title)}</h1>
${brief}
</header>
${html}
</main>
<script>${assets.highlightJs}</script>
<script>hljs.highlightAll();</script>
${mermaidTag}
</body>
</html>
`;
}

export async function renderFile(path, assets) {
  return renderMdx(await readFile(path, "utf8"), assets ?? (await loadAssets()));
}
