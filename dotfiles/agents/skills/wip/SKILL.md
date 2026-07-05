---
name: wip
description: >
  Summarise the work you have in progress across all local repositories. Reads the
  repos-status.json snapshot written by `repos ls` (branch, unmerged commits, dirty
  files, last activity per repo) and turns it into a readable summary grouped by state,
  surfacing the Azure DevOps work items in flight. Use when the user asks "what am I
  working on", "what's in progress", "wip", "where did I leave off", or wants an
  overview of unfinished work before switching context.
argument-hint: "[repo filter] [--refresh]"
---

Summarise in-progress work across all local repos from the `repos ls` snapshot.

**Arguments:** `$ARGUMENTS`
- An optional plain word filters to repos whose name or branch contains it.
- `--refresh` forces the snapshot to be regenerated before summarising.

## Step 1: Locate and freshen the snapshot

The snapshot lives at `$REPO_STATUS` (falls back to `$REPO_HOME/repos-status.json`, i.e.
`/mnt/c/Code/repos-status.json`). It is written every time `repos ls` runs.

```bash
STATUS="${REPO_STATUS:-/mnt/c/Code/repos-status.json}"
```

Decide whether to refresh:

- If the file is missing, or `--refresh` was passed, run `repos ls` to (re)generate it.
- Otherwise read `.generated` and report its age. If it is older than about an hour, tell
  the user and offer to refresh with `repos ls`, but do not block on it.

`repos ls` is a shell function from the dotfiles, so invoke it through an interactive
shell if it is not already defined:

```bash
bash -ic 'repos ls' >/dev/null 2>&1
```

## Step 2: Read the snapshot

```bash
jq . "$STATUS"
```

Each entry in `.repos` has: `name`, `path`, `branch`, `default_branch`, `merged`,
`dirty_files`, `unmerged_commits`, `last_activity` (YYYY-MM-DD), `commits` (newest first,
each with `sha`, `date`, `subject`), and `changed_files`.

If a repo filter was given, keep only entries whose `name` or `branch` contains it.

## Step 3: Interpret each repo

For every repo, work out what the change is about and how far along it is:

- **Theme.** Infer it from the branch name and the commit subjects. The commit subjects
  are the strongest signal for what the work delivers.
- **Work items.** Pull every `AB#<id>` referenced in branch names and commit subjects.
  These are the Azure DevOps items the work maps to. Collect them so they can be listed
  together.
- **State.** Classify each repo into one of:
  - *Active* — has `unmerged_commits > 0` and recent `last_activity`.
  - *Uncommitted only* — on the default branch with `dirty_files > 0` and no unmerged
    commits (scratch edits not yet committed).
  - *Looks done* — `merged: true` (off the default branch but nothing unmerged), i.e.
    shipped and awaiting cleanup with `repos clear`.
  - *Stale* — `last_activity` more than ~14 days ago; call these out so they are not
    forgotten.
- **Uncommitted risk.** Note repos with `dirty_files > 0`, since that work is not yet
  captured in a commit.

## Step 4: Present the summary

Lead with a one-line headline (for example, "6 repos with work in progress across 4
work items"). Then group by state, most active first. For each repo give a compact line:

```
qtms-ftp-uploader  (work/35887-happy-path-s3)  AB#35887
  S3 happy-path upload: config-driven LocalStack client + container tests
  6 commits, last 2026-07-05, clean tree
```

Keep it scannable. Do not dump every commit; synthesise the theme and cite counts and
dates. Flag anything that needs attention: uncommitted changes, stale branches, or
branches that look merged and can be cleared.

Close with the distinct work items in flight, e.g. `In flight: AB#35887, AB#35897`.

## Step 5: Offer follow-ups

Offer, without doing them unprompted:

- Look up any `AB#` item for its title and state (`cli-anything-azdo --json workitem show <id>`).
- Dig into a specific repo (`cd` to its `path` under `$REPO_HOME` and run `git log`/`git diff`).
- Tidy up: `repos clear` for merged branches, or commit the dirty repos.

## Notes

- Read-only over the snapshot. The only state-changing action is regenerating it with
  `repos ls`, and only on refresh.
- Follow `/writing-conventions` for the summary prose (UK English, no em dashes, no filler).
