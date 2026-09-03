#!/bin/bash
# Builds the per-agent instruction files (Claude CLAUDE.md, pi AGENTS.md) from the
# shared template.md, and wires up skills for both agents by symlinking every personal
# skill (this folder) and every work skill (docs-claude-helpers) into each agent's home
# skills folder. Run after editing template.md, the personal skills, or to re-link.

set -euo pipefail

# Path to the shared work helpers repo (provides CLAUDE-template.md and the work skills).
CLAUDE_ORG_REPO="/mnt/c/Code/_docs/docs-claude-helpers"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TEMPLATE="$SCRIPT_DIR/template.md"

CLAUDE_HOME="$HOME/.claude"
PI_HOME="$HOME/.pi/agent"

# Max characters allowed in a skill's frontmatter description. Skills whose
# description exceeds this are materialised as a real folder (siblings symlinked,
# SKILL.md rewritten with a truncated description) instead of a plain dir symlink.
MAX_DESC_CHARS=1024

# Per-agent section exclusions: headings (exact-line match) to strip from one
# agent's output so CLAUDE.md and AGENTS.md can diverge. Add a line per heading.
CLAUDE_EXCLUDES=(
    "### Web CLI (\`web\`)"   # Claude Code has built-in web search/fetch tools
)
AGENTS_EXCLUDES=()

# Strip markdown sections by heading from expanded content.
# Usage: echo "$content" | strip_sections "## Heading One" "## Heading Two" ...
# Removes each matched heading and everything up to the next heading
# at the same or higher level (or EOF).
strip_sections() {
    local excludes=("$@")
    [ ${#excludes[@]} -eq 0 ] && cat && return

    local skipping=false
    local skip_level=0

    while IFS= read -r line || [ -n "$line" ]; do
        # Strip trailing CR for consistent matching
        local clean="${line%$'\r'}"

        # Check if this line is a markdown heading
        if [[ "$clean" =~ ^(#{1,6})[[:space:]] ]]; then
            local hashes="${BASH_REMATCH[1]}"
            local level=${#hashes}

            if $skipping; then
                # Stop skipping when we hit a heading at same or higher level
                if [ "$level" -le "$skip_level" ]; then
                    skipping=false
                fi
            fi

            if ! $skipping; then
                # Check if this heading matches any exclude pattern
                for ex in "${excludes[@]}"; do
                    if [ "$clean" = "$ex" ]; then
                        skipping=true
                        skip_level=$level
                        break
                    fi
                done
            fi
        fi

        if ! $skipping; then
            echo "$line"
        fi
    done
}

# Recursively expand @filename.md references in a file.
# Tracks visited files to prevent circular includes.
# Supports --exclude "## Heading" on @include lines to strip sections.
# An @ref not found relative to the current file falls back to $CLAUDE_ORG_REPO.
expand_file() {
    local file="$1"
    local base_dir
    base_dir="$(dirname "$file")"
    shift
    local visited=("$@")

    # Circular include guard
    local real_path
    real_path="$(realpath "$file" 2>/dev/null || echo "$file")"
    for v in "${visited[@]}"; do
        if [ "$v" = "$real_path" ]; then
            echo "<!-- WARNING: circular include detected for $(basename "$file"), skipping -->"
            return
        fi
    done
    visited+=("$real_path")

    while IFS= read -r line || [ -n "$line" ]; do
        # Match lines that are @filename.md with optional --exclude flags
        if [[ "$line" =~ ^[[:space:]]*@([A-Za-z0-9_/.:-]+\.md)(.*)?$ ]]; then
            local ref="${BASH_REMATCH[1]}"
            local rest="${BASH_REMATCH[2]}"
            local ref_path="$base_dir/$ref"

            # Fall back to the work helpers repo when not found locally
            if [ ! -f "$ref_path" ] && [ -f "$CLAUDE_ORG_REPO/$ref" ]; then
                ref_path="$CLAUDE_ORG_REPO/$ref"
            fi

            # Parse --exclude "## Heading" flags from the rest of the line
            local -a excludes=()
            local parse_rest="$rest"
            local exclude_re='--exclude[[:space:]]+"([^"]*)"(.*)'
            while [[ "$parse_rest" =~ $exclude_re ]]; do
                excludes+=("${BASH_REMATCH[1]}")
                parse_rest="${BASH_REMATCH[2]}"
            done

            if [ -f "$ref_path" ]; then
                if [ ${#excludes[@]} -gt 0 ]; then
                    expand_file "$ref_path" "${visited[@]}" | strip_sections "${excludes[@]}"
                else
                    expand_file "$ref_path" "${visited[@]}"
                fi
            else
                echo "<!-- WARNING: $ref not found, skipping -->"
                echo "$line"
            fi
        else
            echo "$line"
        fi
    done < "$file"
}

# Build an agent instruction file from the shared template.
# Any further arguments are markdown headings to strip from this agent's
# output only (exact-line match), letting CLAUDE.md and AGENTS.md diverge.
# Usage: build_for <harness-name> <output-path> ["## Heading" ...]
build_for() {
    local harness="$1"
    local out="$2"
    shift 2
    local excludes=("$@")

    mkdir -p "$(dirname "$out")"

    local previous_lines=""
    [ -f "$out" ] && previous_lines=$(wc -l < "$out")

    # Replace a pre-existing symlink (e.g. CLAUDE.md -> AGENTS.md) with a real file
    [ -L "$out" ] && rm -f "$out"

    {
        echo "<!-- AUTO-GENERATED by sync-agents.sh — do not edit directly -->"
        echo "<!-- Edit dotfiles/agents/template.md or docs-claude-helpers/CLAUDE-template.md instead -->"
        echo ""
        expand_file "$TEMPLATE" | strip_sections "${excludes[@]}"
    } > "$out"

    # Substitute the harness placeholder and normalise line endings to LF
    sed -i "s/{{HARNESS}}/${harness}/g; s/\r//" "$out"

    local lines
    lines=$(wc -l < "$out")
    if [ -z "$previous_lines" ]; then
        echo "Built $out ($lines lines, new)"
    elif [ "$lines" -ne "$previous_lines" ]; then
        echo "Built $out ($lines lines, was $previous_lines)"
    else
        echo "Built $out ($lines lines)"
    fi
}

# Symlink every work skill and every personal skill into an agent's skills folder.
# Personal skills are linked last so they override work skills of the same name.
# Usage: link_skills <home-skills-dir>
link_skills() {
    local dir="$1"

    # Replace a whole-folder symlink (e.g. ~/.claude/skills -> helpers/skills) with a real dir
    [ -L "$dir" ] && rm -f "$dir"
    mkdir -p "$dir"

    # Clear out stale symlinks only, leaving any real files untouched
    find "$dir" -maxdepth 1 -type l -delete

    local src skill name
    for src in "$CLAUDE_ORG_REPO/skills" "$SCRIPT_DIR/skills"; do
        [ -d "$src" ] || continue
        for skill in "$src"/*/; do
            [ -d "$skill" ] || continue
            name="$(basename "$skill")"
            # Replace whatever is there (stale copy, dir, or older link) so the result is
            # always clean — personal skills are linked last and thus win.
            rm -rf "$dir/$name"
            link_skill "${skill%/}" "$dir/$name"
        done
    done

    echo "Linked skills into $dir ($(find "$dir" -maxdepth 1 -mindepth 1 | wc -l) skills)"
}

# Link a single skill into an agent's skills folder. If its SKILL.md description is
# within MAX_DESC_CHARS, symlink the whole folder. Otherwise materialise a real folder
# with siblings symlinked and a SKILL.md whose description is truncated.
# Usage: link_skill <source-skill-dir> <dest-path>
link_skill() {
    local skill="$1"
    local dest="$2"
    python3 - "$skill" "$dest" "$MAX_DESC_CHARS" <<'PY'
import os, re, sys

skill, dest, maxlen = sys.argv[1], sys.argv[2], int(sys.argv[3])
skillmd = os.path.join(skill, "SKILL.md")

def extract(fm_lines):
    """Return (start, end, text) for the description, or None. end is exclusive."""
    for i, line in enumerate(fm_lines):
        m = re.match(r"^description:\s*(.*)$", line)
        if not m:
            continue
        val = m.group(1).strip()
        if re.fullmatch(r"[>|][+-]?", val):  # block scalar: consume indented lines
            j = i + 1
            buf = []
            while j < len(fm_lines) and (fm_lines[j].strip() == "" or fm_lines[j].startswith((" ", "\t"))):
                buf.append(fm_lines[j].strip())
                j += 1
            return i, j, " ".join(x for x in buf if x)
        return i, i + 1, val.strip('"').strip("'")
    return None

needs_trunc = False
if os.path.isfile(skillmd):
    text = open(skillmd, encoding="utf-8").read()
    fm = re.match(r"^(---\n)(.*?\n)(---\n?)(.*)$", text, re.S)
    if fm:
        fm_lines = fm.group(2).splitlines()
        found = extract(fm_lines)
        if found and len(found[2]) > maxlen:
            needs_trunc = True
            start, end, desc = found
            truncated = desc[:maxlen].rstrip()
            new_fm = fm_lines[:start] + ["description: |-", "  " + truncated] + fm_lines[end:]
            new_text = fm.group(1) + "\n".join(new_fm) + "\n" + fm.group(3) + fm.group(4)
            os.makedirs(dest, exist_ok=True)
            for entry in os.listdir(skill):
                if entry == "SKILL.md":
                    continue
                os.symlink(os.path.join(skill, entry), os.path.join(dest, entry))
            with open(os.path.join(dest, "SKILL.md"), "w", encoding="utf-8") as f:
                f.write(new_text)
            print(f"  truncated description for {os.path.basename(skill)} ({len(desc)} -> {len(truncated)} chars)")

if not needs_trunc:
    os.symlink(skill, dest)
PY
}

build_for "Claude Code" "$CLAUDE_HOME/CLAUDE.md" "${CLAUDE_EXCLUDES[@]}"
build_for "the pi-coding-agent harness" "$PI_HOME/AGENTS.md" "${AGENTS_EXCLUDES[@]}"

link_skills "$CLAUDE_HOME/skills"
link_skills "$PI_HOME/skills"
