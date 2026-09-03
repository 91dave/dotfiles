# Coding Agent Instructions

@output.md

## Environment

You are a model running in {{HARNESS}}. You are running under WSL on a windows system. Use linux commands as usual with the following exceptions:

- use `podman.exe` instead of `docker` for all container operations
- use `dotnet.exe` not `dotnet`
- always run `git commit` and `git push` as separate commands
- use `pwsh.exe` not `pwsh`
- use `rg` (ripgrep) instead of `grep` for fast recursive text search
  - **`-r` means `--replace`, not recursive.** `rg` is recursive by default, and `rg -rn "pattern"` silently replaces every match with `n`. Use `rg -n` for line numbers.
- use `fdfind` instead of `find` for fast file finding

## Additional Tools

All tools below are on PATH and support `--help` for full usage.

### IcePanel CLI (`icepanel-cli`)

Query and update the C4 architecture model. Use `--json` for structured output.

```bash
icepanel-cli --json object list -n "<name>"
icepanel-cli --json connection list --origin "<object-id>"
```

**Trigger:** When the user asks about architectural components, references C4 model terms (containers, systems, connections), or asks what a service talks to.

### Azure DevOps CLI (`azdo-cli`)

Query and update work items, comments, and queries. Use `--json` for structured output.

```bash
azdo-cli --json workitem show 12345
azdo-cli --json workitem children 12345
azdo-cli comment add 12345 comment.md
```

**Trigger:** When `AB#12345` is mentioned, immediately fetch work item details before planning work.

### Web CLI (`web`)

Search the web and fetch pages as clean markdown (no API keys needed).

```bash
web search "query terms"
web fetch "https://example.com"
```

@repos.md
@pkg.md

## Capturing Output From Long-Running Commands

`tee` the full output to a file, then inspect the tail. Re-running a
multi-minute build to see an error the tail referenced is the failure this avoids.

Write logs to `/tmp`, not the session scratchpad — shorter to reference, and they
are disposable. Name each one for the repo or task so a parallel session does not
clobber it.

```bash
# ✗ Loses output:
dotnet.exe build | tail -n40

# ✓ Full log captured, tail shown inline:
dotnet.exe build 2>&1 | tee /tmp/publication-build.log | tail -n40
npm test       2>&1 | tee /tmp/frontend-test.log      | tail -n40

# Follow up without re-running:
rg -n "error|FAIL" /tmp/publication-build.log
```

## WSL ↔ Windows Path Handling for `.exe` Commands

Windows executables cannot resolve WSL paths (`/mnt/c/...`), so convert to
Windows-style (`C:/Code/...`) when passing a file path to an `.exe`. `$USERPROFILE`
does not expand under WSL; use `$USERPROFILE_WIN` (→ `C:/Users/...`).

```bash
pwsh.exe -File "/mnt/c/Code/scripts/helper.ps1"              # ✗ fails
pwsh.exe -File "C:/Code/scripts/helper.ps1"                  # ✓
pwsh.exe -File "$USERPROFILE_WIN/.claude/skills/helper.ps1"  # ✓
```

@CLAUDE-template.md --exclude "## Technology Choices" --exclude "## Architecture" --exclude "### Planning and Execution" --exclude "## Testing Strategy"

@visual-plan.md
