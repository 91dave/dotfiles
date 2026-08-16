const TASK_TYPES = new Set([
  "Functional",
  "Refactor",
  "Test",
  "Documentation",
  "Infrastructure",
]);

const CALLOUT_TONES = new Set(["info", "decision", "risk", "warning", "success"]);

export function escapeHtml(value) {
  return String(value ?? "")
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}

function slug(value) {
  return String(value ?? "")
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-|-$/g, "");
}

function malformedComponent(name, requirement) {
  return `<div class="vp-error"><strong>${escapeHtml(name)}</strong> ${escapeHtml(requirement)}</div>`;
}

function callout({ tone = "info" }, children = "") {
  const safeTone = CALLOUT_TONES.has(tone) ? tone : "info";
  return `<aside class="vp-callout vp-callout--${safeTone}"><div class="vp-callout__label">${safeTone}</div><div class="vp-callout__body">${children}</div></aside>`;
}

function directoriesNotSharedWithPrevious(segments, previousSegments) {
  return segments.flatMap((segment, depth) =>
    previousSegments[depth] === segment
      ? []
      : [
          `<li class="vp-tree__dir" style="--depth:${depth}"><span class="vp-tree__name">${escapeHtml(segment)}/</span></li>`,
        ],
  );
}

function fileTree({ title, entries }) {
  if (!Array.isArray(entries) || entries.length === 0) {
    return malformedComponent("FileTree", "needs a non-empty entries array.");
  }

  let previousSegments = [];
  const rows = entries.map((entry) => {
    const path = String(entry?.path ?? "").replace(/^\/+/, "");
    const segments = path.split("/").filter(Boolean);
    const file = segments.pop() ?? path;

    const dirs = directoriesNotSharedWithPrevious(segments, previousSegments);
    previousSegments = segments;

    const change = entry?.change ? String(entry.change) : "";
    const badge = change
      ? `<span class="vp-badge vp-badge--${slug(change)}">${escapeHtml(change)}</span>`
      : "";
    const note = entry?.note
      ? `<span class="vp-tree__note">${escapeHtml(entry.note)}</span>`
      : "";

    return [
      ...dirs,
      `<li class="vp-tree__file" style="--depth:${segments.length}"><span class="vp-tree__name">${escapeHtml(file)}</span>${badge}${note}</li>`,
    ].join("");
  });

  const heading = title
    ? `<div class="vp-tree__title">${escapeHtml(title)}</div>`
    : "";
  return `<div class="vp-tree">${heading}<ul class="vp-tree__list">${rows.join("")}</ul></div>`;
}

function field(label, value) {
  if (value === undefined || value === null || value === "") return "";
  const body = Array.isArray(value)
    ? `<ul>${value.map((item) => `<li>${escapeHtml(item)}</li>`).join("")}</ul>`
    : `<p>${escapeHtml(value)}</p>`;
  return `<div class="vp-task__field"><dt>${escapeHtml(label)}</dt><dd>${body}</dd></div>`;
}

function tasks({ items }) {
  if (!Array.isArray(items) || items.length === 0) {
    return malformedComponent("Tasks", "needs a non-empty items array.");
  }

  const cards = items.map((item, index) => {
    const type = String(item?.type ?? "");
    const typeClass = TASK_TYPES.has(type) ? slug(type) : "unknown";
    const dependsOn = Array.isArray(item?.dependsOn) ? item.dependsOn : [];
    const deps = dependsOn.length
      ? `<div class="vp-task__deps">depends on ${dependsOn.map((d) => `<code>${escapeHtml(d)}</code>`).join(", ")}</div>`
      : "";

    return `<article class="vp-task" id="task-${escapeHtml(item?.id ?? index + 1)}">
<header class="vp-task__head">
<span class="vp-task__order">${index + 1}</span>
<h3 class="vp-task__title">${escapeHtml(item?.title ?? "Untitled task")}</h3>
<span class="vp-badge vp-badge--${typeClass}">${escapeHtml(type || "Unknown")}</span>
</header>
${deps}
<dl class="vp-task__fields">
${field("Objective", item?.objective)}
${field("Inputs", item?.inputs)}
${field("Outputs", item?.outputs)}
${field("Success criteria", item?.successCriteria)}
</dl>
</article>`;
  });

  return `<div class="vp-tasks">${cards.join("")}${dependencyGraphDerivedFromDependsOn(items)}</div>`;
}

function dependencyGraphDerivedFromDependsOn(items) {
  const orderById = new Map(
    items.map((item, index) => [String(item?.id ?? index + 1), index + 1]),
  );
  const edges = items.flatMap((item, index) =>
    (item?.dependsOn ?? []).flatMap((dep) => {
      const from = orderById.get(String(dep));
      return from ? [`  T${from} --> T${index + 1}`] : [];
    }),
  );
  if (edges.length === 0) return "";

  const nodes = items.map(
    (item, index) =>
      `  T${index + 1}["${String(item?.title ?? "").replace(/"/g, "'")}"]`,
  );
  const source = ["flowchart LR", ...nodes, ...edges].join("\n");
  return `<div class="vp-tasks__graph"><div class="vp-tree__title">Dependencies</div>${mermaidWithSourceFallback(source)}</div>`;
}

export function mermaidWithSourceFallback(source) {
  return `<pre class="mermaid">${escapeHtml(source)}</pre>`;
}

export const components = { Callout: callout, FileTree: fileTree, Tasks: tasks };

export const PAIRED = new Set(["Callout"]);
