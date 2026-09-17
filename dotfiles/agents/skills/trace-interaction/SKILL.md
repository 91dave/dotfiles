---
name: trace-interaction
description: >
  Trace an interaction or flow across codebases to identify every application, service and data
  store involved, hopping between repos to follow service-to-service calls, queue messages and
  data access. Use when asked to trace, map, or document a business function, user journey, or
  interaction flow across services. Produces a step-by-step narrative and a table of the
  components involved with their role in the flow.
  Invoke manually: /trace-interaction <interaction> [starting point]
argument-hint: "<interaction description> [starting repo, endpoint or page]"
---

# Trace Interaction

Follow a described interaction from its entry point through every service, queue and data store it
touches, hopping between repositories as the call chain crosses repo boundaries. The result is a
narrative of what actually executes plus a table of the components involved.

## User Input

The user must provide:

1. **Interaction description** - what the user or system does (e.g. "uploading a Kaltura asset")
2. **Starting point(s)** - one or more of:
   - Application or repo name (e.g. `qts-assets`, `qtui-front-end`)
   - API endpoint (e.g. `POST /{version}/{clientKey}/assets/create`)
   - Page or UI feature (e.g. "the upload page in the DAM")

If the user has not provided enough detail, ask before proceeding.

## Workflow

### Phase 1 - Locate the repos

Repos are cloned to different places on different machines. Never assume a drive, a root directory,
or that any particular helper command exists.

**The user's `CLAUDE.md` is the source of truth for finding local checkouts.** Most people document
one mechanism there: a CLI that resolves a repo name to a path, a root directory that clones sit
under, or a naming convention. Read it and use exactly what it describes. Do not substitute a
command of your own, and do not go looking for a mechanism it does not mention.

1. **An explicit path in the arguments.** If the user gave an absolute path to a checkout, use it.
2. **The mechanism documented in the user's `CLAUDE.md`.** This is the normal route. Follow it as
   written, including any disambiguation it describes for ambiguous names.
3. **`repos_root` from `~/.claude/workspace-config.json`**, if that file exists and sets it, giving
   `<repos_root>/<repo-name>`:
   ```bash
   CONFIG="$HOME/.claude/workspace-config.json"
   [ -f "$CONFIG" ] && REPOS_ROOT=$(python3 -c "import json,sys;print(json.load(open(sys.argv[1])).get('repos_root',''))" "$CONFIG")
   [ -n "$REPOS_ROOT" ] && [ -d "$REPOS_ROOT/<repo-name>" ] && echo "$REPOS_ROOT/<repo-name>"
   ```
4. **If neither documents a mechanism**, say so once, plainly, before continuing:
   > Your CLAUDE.md doesn't say how to find local repo checkouts and no repos_root is configured, so
   > I'm falling back to searching from the working directory and reading from GitHub. Adding that
   > guidance to CLAUDE.md will make this and other skills faster.

   Then fall back, in order:
   - **Walk up from the working directory**, looking for the repo as a sibling of the current
     checkout:
     ```bash
     dir=$(pwd); while [ "$dir" != "/" ]; do
       [ -d "$dir/<repo-name>/.git" ] && { echo "$dir/<repo-name>"; break; }
       dir=$(dirname "$dir")
     done
     ```
   - **Read from the remote without cloning.** For a trace that needs one or two files from a repo,
     this beats a clone:
     ```bash
     gh search repos --owner <org> <repo-name>
     gh api repos/<org>/<repo-name>/contents/<path/to/File.cs> --jq .content | base64 -d
     ```
   - **Ask the user** for the absolute path, or for permission to clone.

Record the resolved absolute path for each repo and reuse it; the Read tool needs absolute paths. A
repo you cannot resolve is reported as a gap in the output, never guessed at or inferred from a
similarly named one.

### Phase 2 - Find entry points

Based on the starting information, find the relevant code entry points.

**For API endpoints**, search for the route or controller:

```bash
# Search gateway routing files for the endpoint path
rg -n "UpstreamPathTemplate.*assets/create" -g "gateway.*.json"

# Search controllers
rg -n "\[Http(Get|Post|Put|Delete|Patch)\]" -g "*.cs" -l
rg -n "the-route-fragment" -g "*.cs"
```

**For UI pages**, search the frontend repo:

```bash
rg -n "route.*upload" -g "*.ts" -g "*.tsx"
```

**For background jobs**, search for message handlers or scheduled tasks:

```bash
rg -n "\[MQHandler\(typeof\(" -g "*.cs"
rg -n "RegularTask|BackgroundService" -g "*.cs"
```

### Phase 3 - Trace service-to-service calls

From each entry point, trace outbound calls to other services. Look for:

#### IServiceClient calls (synchronous HTTP to other services)

```bash
rg -n "IServiceClient|I\w+ServiceClient" -g "*.cs"
```

These indicate the current service calls another service's API. Note the target service. The routing
target is often declared on the request DTO itself (a `ServiceGateway` property or equivalent)
rather than at the call site, so check the DTO before assuming which service receives the call.

#### IQueueClient calls (asynchronous message queue)

```bash
rg -n "IQueueClient|EnqueueMessage" -g "*.cs"
```

Find what message types are enqueued:

```bash
rg -n "new \w+Message\(" -g "*.cs"
rg -n "EnqueueMessage.*new " -g "*.cs"
```

#### Data store access (databases, S3, Redis, and so on)

```bash
rg -n "IUnitOfWork|I\w+UnitOfWork|IS3|IRedis|ICacheService" -g "*.cs"
```

#### Conditional paths

Watch for feature flags and configuration switches that select between a legacy and a new path. The
two branches often reach different components. Say which branch you traced and note the other.

### Phase 4 - Cross-repo resolution

When you find a message type, service client interface, or request/response DTO that is not defined
in the current repo, use code search to find where it lives:

```bash
# Find where a message class is defined
gh search code "class ProcessAssetMessage" --owner <org> --language C# --json repository,path

# Find where a message is handled
gh search code "MQHandler(typeof(ProcessAssetMessage))" --owner <org> --language C# --json repository,path

# Find request/response DTOs
gh search code "class CreateAssetRequest" --owner <org> --language C# --json repository,path

# Find service client interfaces
gh search code "interface IMetadataServiceClient" --owner <org> --language C# --json repository,path
```

**Important patterns:**

- Message classes are typically defined in `Quartex.{Domain}.Api` projects (NuGet packages)
- Message handlers live in `Quartex.{Domain}.Background` projects
- Service client interfaces are in `Quartex.{Domain}.Api` packages
- Request/Response DTOs may be in the API project or a shared package (`qtpkg-*`)

**Defining a contract is not being in the flow.** A package named for one domain routinely carries
the DTOs and messages that another domain's services exchange. The service that owns the package may
never execute during the interaction. Confirm a handler or endpoint actually runs before adding a
component to the table.

When a new repo turns out to handle a message or request, resolve it with the Phase 1 ladder and
repeat from Phase 2 to trace further calls from that service.

### Phase 5 - Output

Produce the following.

**1. A summary of the flow.** A short numbered list, one step per hop, stating what happens at each.
Call out explicitly where a handoff is synchronous versus asynchronous, and where a caller awaits
only the enqueue rather than the work itself. That distinction is usually the point of the trace.

**2. Step-by-step detail.** One section per step, naming the concrete file and member that does the
work, with the relevant line or two of code quoted where it clarifies routing or a decision. Use
repo-relative paths so a reader can find them in their own checkout.

**3. A components table:**

| Application / Data Store | Repo | Role in this interaction |
|---|---|---|
| Assets API | `qts-assets` | Receives the upload request; enqueues the processing message |
| Message Queue | - | Async transport between the API and the background service |

- **Application / Data Store**: the human-friendly name of the service or store
- **Repo**: the repo name (omit for infrastructure and data stores)
- **Role in this interaction**: one line on what this component does in *this specific* flow

**4. A "not in the runtime path" table**, whenever the trace ruled out something a reader would
reasonably expect to be involved:

| Candidate | Why it looks involved | Reality |
|---|---|---|
| Metadata microservice | The request DTO lives in its contract package | Provides the contract only; the request routes elsewhere |

Offer to write the result to a markdown file named for the interaction (for example
`upload-kaltura-asset-trace.md`). Head any such file with a note that it was generated by Claude and
the model used, and list the repos traced.

## Iteration

This is an **iterative** process. Each service you discover may call further services. Continue
tracing until you reach leaf nodes: services that call nothing further, or data stores.

Keep a running list of discovered components to avoid circular traversal. If service A calls service
B which calls service A, note the cycle and stop.

Typical depth is 2-4 levels. If you reach 5 or more, pause and confirm with the user before
continuing.

## Composability

The components table is designed to be consumed by other skills, which may enrich it with
architecture-model identifiers, ownership, or deployment detail. Keep the table complete and
accurate on its own terms; do not add columns for a downstream consumer. This skill knows nothing
about what calls it.
