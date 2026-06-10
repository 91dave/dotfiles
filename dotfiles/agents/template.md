# Coding Agent Environment

You are a model running in {{HARNESS}}. You are running under WSL on a windows system. Use linux commands as usual with the following exceptions:

- use `podman.exe` instead of `docker` for all container operations
- use `dotnet.exe` not `dotnet`
- use `git.exe` not `git`
    - always run `git.exe commit` and `git.exe push` as separate commands
- use `gh.exe` not `gh`
- use `pwsh.exe` not `pwsh`
- use `rg` (ripgrep) instead of `grep` for fast recursive text search
- use `fdfind` instead of `find` for fast file finding

## Additional Tools

All tools below are on PATH and support `--help` for full usage.

### IcePanel CLI (`cli-anything-icepanel`)

Query and update the C4 architecture model. Use `--json` for structured output.

```bash
cli-anything-icepanel --json object list -n "<name>"
cli-anything-icepanel --json connection list --origin "<object-id>"
```

**Trigger:** When the user asks about architectural components, references C4 model terms (containers, systems, connections), or asks what a service talks to.

### Azure DevOps CLI (`cli-anything-azdo`)

Query and update work items, comments, and queries. Use `--json` for structured output.

```bash
cli-anything-azdo --json workitem show 12345
cli-anything-azdo --json workitem children 12345
cli-anything-azdo comment add 12345 comment.md
```

**Trigger:** When `AB#12345` is mentioned, immediately fetch work item details before planning work.

### Web CLI (`web`)

Search the web and fetch pages as clean markdown (no API keys needed).

```bash
web search "query terms"
web fetch "https://example.com"
```

### Repo Finder (`repo-find`)

Locate local repositories by name from a cached repo list.

```bash
repo-find documents        # → full path to matching repo
repo-find --list terraform
```

**Workflow:** `repo-find <term>` → disambiguate if needed → `cd` to path before working.

## ripgrep (`rg`) and `fd` Gotchas

**`rg` is not `grep` — flags differ in important ways:**

- **`-r` means `--replace`, NOT recursive.** `rg` is recursive by default. Using `rg -rn "pattern"` replaces every match with the letter `n` in the output, producing garbled results. Use `rg -n` for line numbers.
- **No `--include` flag.** Use `-g`/`--glob` for file type filtering (e.g. `-g "*.tf"`).
- **No `-R` flag.** Recursion is always on; use `--max-depth` to limit it.

```bash
# ✗ Common mistakes (grep habits):
rg -rn "pattern"              # Replaces matches with 'n' in output!
rg --include "*.tf" "pattern"  # Unknown flag

# ✓ Correct ripgrep usage:
rg -n "pattern"               # Recursive search with line numbers
rg -n "pattern" -g "*.tf"     # Filter to .tf files
rg -l "pattern"               # List matching files only
```

## Looking Up Source for Third-Party / NuGet / Internal Package Code

When you need to read the source of a type that lives in a NuGet package, an internal shared library, or any other dependency that is not in the current repo:

- **Do not** rummage through `~/.nuget`, `bin/`, `obj/`, or decompile DLLs. Compiled binaries are noisy and the symbol names rarely line up cleanly with the source.
- **Do** locate the source repo and read the `.cs` / `.ts` / etc. directly.

Preferred order:

1. **`gh search code`** — find the type, member, or string across the GitHub org. This works for internal `qtpkg-*` packages and any other repos you have access to.
   ```bash
   gh.exe search code --owner amdigital-co-uk "class WebsiteInfoModule"
   gh.exe search code --owner amdigital-co-uk --filename "WebsiteInfoModule.cs"
   ```
2. **`repo-find <name>`** — once you know the repo, check whether it's already cloned locally and `cd` to it for fast `rg` / `read` access.
   ```bash
   repo-find qtpkg-core
   ```
3. **`gh.exe api`** — if the repo isn't on disk and cloning is overkill, fetch the specific file via the GitHub API rather than cloning.
   ```bash
   gh.exe api repos/amdigital-co-uk/qtpkg-core/contents/path/to/File.cs --jq .content | base64 -d
   ```

**Trigger:** any time a stack trace, type name, or behavioural question points at code outside the current repo (e.g. `Quartex.Common.*`, `Quartex.Core.*`, third-party middleware).

## Commenting Policy

Be very sparing with adding comments, regardless of code/file type. Comments should explain WHY not HOW, and should only be used for genuinely non-obvious scenarios. Prefer a single
comment at the top of a file or method rather than in-line. The best comment is no comment at all.

## Capturing Output From Long-Running Commands

When inspecting only the head/tail of a build or test run, **`tee` the full
output to a file first** so you don't have to re-run the command for more
context.

- `| tail -n40` discards everything else — if the tail references an earlier
  error, you're forced to re-run (often a multi-minute build).
- `tee` keeps the full log on disk for cheap follow-up with `rg` or `less`.
- Use `/tmp` for the log file; redirect stderr with `2>&1` for build tools.

```bash
# ✗ Loses output:
dotnet.exe build | tail -n40

# ✓ Full log captured, tail shown inline:
dotnet.exe build 2>&1 | tee /tmp/build.log | tail -n40
npm test       2>&1 | tee /tmp/test.log  | tail -n40

# Follow up without re-running:
rg -n "error|FAIL" /tmp/build.log
```

## WSL ↔ Windows Path Handling for `.exe` Commands

When calling Windows executables (e.g. `pwsh.exe`) with file path arguments:

- **WSL paths (`/mnt/c/...`) do not work** as arguments to `.exe` commands — Windows executables cannot resolve them.
- **`$USERPROFILE` is not available in WSL** — it won't expand to anything useful, use the following instead
  - `$USERPROFILE_WIN` - expands to the windows version of the user profile - i.e. `C:/Users/...`
- **Use Windows-style paths** (`C:/Code/...` or `C:\Code\...`) when passing file paths to `.exe` commands.
- If a skill or script is located at a WSL path like `/mnt/c/Code/foo/bar.ps1`, convert it to `C:/Code/foo/bar.ps1` before passing to `pwsh.exe -File`.

**Example:**
```bash
# ✗ These will fail:
pwsh.exe -File "/mnt/c/Code/scripts/helper.ps1"
pwsh.exe -File "$USERPROFILE\.claude\skills\helper.ps1"

# ✓ This works:
pwsh.exe -File "C:/Code/scripts/helper.ps1"
pwsh.exe -File "$USERPROFILE_WIN/.claude/skills/helper.ps1"
```

@CLAUDE-template.md --exclude "## Technology Choices"

