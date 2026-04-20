# Coding Agent Environment

You are a model running in the pi-coding-agent harness. You are running under WSL on a windows system. Use linux commands as usual with the following exceptions:

- use `podman.exe` instead of `docker` for all container operations
- use `dotnet.exe` not `dotnet`
- use `git.exe` not `git`
- use `gh.exe` not `gh`

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
cli-anything-azdo comment add 12345 "Comment text"
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

@CLAUDE.md

