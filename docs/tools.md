# Standalone CLI Tools

Lightweight scripts symlinked into `~/.local/bin/` via `install.sh`. Designed for non-interactive use by coding agents but work fine interactively too.

## web

Search the web and fetch pages as clean markdown. No API keys required.

### Usage

```bash
web search <query>               # Search via DuckDuckGo
web search <query> --max <n>     # Limit number of results (default: 10)
web fetch <url>                  # Fetch a URL as markdown via Jina Reader
web fetch <url> --max <chars>    # Limit output length (default: 8000, max: 20000)
```

### Examples

```bash
web search "rust programming language"
web fetch "https://docs.python.org/3/tutorial/"
web fetch "https://example.com" --max 16000
```

### How it works

- **Search** sends a POST to DuckDuckGo's HTML endpoint, parses results with Python, and outputs numbered markdown entries (title, URL, snippet).
- **Fetch** proxies through [Jina Reader](https://r.jina.ai/) which returns a clean markdown representation of the page, stripped of navigation and ads.
- Set `JINA_API_KEY` for higher Jina rate limits (optional).

---

## repos

Find and manage local repositories from a cached repo list. `repos` is an executable on `PATH`, so agents and non-interactive shells can call it directly. In an interactive shell a `repos()` function of the same name additionally lets `repos cd` change the current directory. Full subcommand reference: [git.md](git.md#repos).

### Usage

```bash
repos ls [term]           # List repos (🔒 readonly, 📝 modified, 🌿 branch, 📁 clean)
repos ls --readonly       # Filter: only archived/readonly repos (also --modified, --active)
repos find [term]         # Raw grep of the cache (plain paths, no decoration)
repos resolve <term>      # Returns full path (fails if ambiguous; GitHub fallback if not cloned)
repos status              # Report/refresh WIP snapshot
repos code <term>         # Open the repo in VS Code
repos ide <term>          # Open the repo's .sln/.slnx in Visual Studio
repos cache               # Rebuild cache and refresh the archived/readonly list
```

### Examples

```bash
repos resolve documents      # → /mnt/c/Code/quartex-services/qtms-documents
repos ls terraform           # List all terraform-related repos
cd "$(repos resolve myapp)"  # cd into a repo by fuzzy name
```

---

## mdserve

Render an MDX plan document (mermaid diagrams, file trees, highlighted code, task breakdowns) as standalone HTML and serve it on `127.0.0.1` for browser review. The renderer behind the `visual-plan` skill. Needs only Node; code lives in `dotfiles/bin/mdserve.d/`.

### Usage

```bash
mdserve serve <plan>                 # Serve on 7842 (free port if taken), re-render per request
mdserve serve <plan> --port <n>      # Fixed port
mdserve serve <plan> --idle <mins>   # Idle minutes before it stops (default 30, 0 = never)
mdserve render <plan>                # Standalone HTML to stdout
mdserve render <plan> --out <file>   # Standalone HTML to a file
mdserve test                         # Renderer and CLI self-check
```

`<plan>` is a `.md`/`.mdx` file or a directory containing `plan.mdx`. The page heading is the body's leading `# H1` if it has one, else frontmatter `title`; frontmatter `tags: [ 'a', 'b' ]` become header chips next to `workItem` (an `AB#123` value links to Azure DevOps). The MDX is evaluated to render it, so only point it at trusted plans.
