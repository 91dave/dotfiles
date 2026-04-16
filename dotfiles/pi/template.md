# Coding Agent Environment

You are a model running in the pi-coding-agent harness. You are running under WSL on a windows system. Use linux commands as usual with the following exceptions:

- use `podman.exe` instead of `docker` for all container operations
- use `dotnet.exe` not `dotnet`
- use `git.exe` not `git`
- use `gh.exe` not `gh`

## Additional Tools

### IcePanel CLI

The `cli-anything-icepanel` tool is available on PATH for querying the IcePanel C4 architecture model. Use it when:

- Answering architecture questions (e.g. what systems does a service talk to)
- Checking C2 container-level interactions
- Verifying whether IcePanel needs updating after code changes

Key commands:

```bash
# Find objects by name
cli-anything-icepanel --json object list -n "<name>"

# List outgoing connections from an object
cli-anything-icepanel --json connection list --origin "<object-id>"

# List incoming connections to an object
cli-anything-icepanel --json connection list --target "<object-id>"

# Get object details
cli-anything-icepanel --json object info "<object-id>"

# See all available commands
cli-anything-icepanel --help
```

### Azure DevOps CLI

The `cli-anything-azdo` tool is available on PATH for querying and updating Azure DevOps work items, comments, and queries. Use it when:

- A work item reference is mentioned (format: `AB#12345`)
- Retrieving work item details, state, or custom fields
- Listing or searching for work items
- Viewing or adding comments on work items
- Checking child tasks under a backlog item
- Creating or updating work items programmatically

Key commands:

```bash
# Show a work item by ID
cli-anything-azdo --json workitem show 12345

# Show a work item with extra/custom fields
cli-anything-azdo --json workitem show 12345 --field Custom.DesignandImplementationNotes

# List all fields on a work item (including custom fields)
cli-anything-azdo --json workitem fields 12345
cli-anything-azdo --json workitem fields 12345 --name Custom.DesignandImplementationNotes

# List child work items of a parent
cli-anything-azdo --json workitem children 12345

# Search work items by title
cli-anything-azdo --json workitem search "search text"

# List work items with filters
cli-anything-azdo --json workitem list --state Active --assigned-to @Me

# List and add comments
cli-anything-azdo --json comment list 12345
cli-anything-azdo comment add 12345 "Comment text"

# Create and update work items
cli-anything-azdo workitem create --type Task --title "New task" --parent 12345
cli-anything-azdo workitem update 12345 --state Closed --field Custom.MyField=value

# Run a raw WIQL query
cli-anything-azdo --json query run "SELECT [System.Id] FROM WorkItems WHERE [System.State] = 'Active'"

# See all available commands
cli-anything-azdo --help
```

### Web Search Workaround

The `web_search` tool has no API key configured and will not work. Instead, use `web_fetch` with DuckDuckGo's HTML endpoint as a workaround:

```
https://html.duckduckgo.com/html/?q=your+search+terms
```

- Google Search is blocked (CAPTCHA), so always use DuckDuckGo
- Use `web_fetch` on individual result URLs to read full page content
- URL-encode query parameters (e.g. spaces as `+`)

### Finding Repositories

The `repo-find` command locates local Quartex repositories from a cached repo list. Use it when:

- You need to find and navigate to a repository
- A GitHub code search identifies a file in a repo you need to work in
- You're asked to make changes across repositories

```bash
# Find a repo by name (returns full path, fails if ambiguous)
repo-find documents        # → /mnt/c/Code/quartex-services/qtms-documents

# List all matching repos (when you need to browse or disambiguate)
repo-find --list terraform

# List all repos
repo-find --list
```

When asked to work in a repository:
1. Use `repo-find <term>` to get the path
2. If ambiguous, narrow the search or ask the user
3. `cd` to the returned path before working

@CLAUDE.md

