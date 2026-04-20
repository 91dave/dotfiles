# Standalone CLI Tools

Lightweight scripts installed to `~/.local/bin/` via `manage.sh`. Designed for non-interactive use by coding agents but work fine interactively too.

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

## repo-find

Locate local repositories by name from a cached repo list.

### Usage

```bash
repo-find <term>          # Returns full path (fails if ambiguous)
repo-find --list          # List all known repos
repo-find --list <term>   # List repos matching a term
```

### Examples

```bash
repo-find documents        # → /mnt/c/Code/quartex-services/qtms-documents
repo-find --list terraform # List all terraform-related repos
```
