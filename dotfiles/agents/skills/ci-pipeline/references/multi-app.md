# Multi-app repos: build and deploy only what changed

Use when one repo produces **more than one deployable image** from a single solution (a
monorepo of services sharing projects). The single-app `ci.yml` does not fit; you need per-app
job groups gated by affected-project detection so a change to one app, or a shared library,
runs only the necessary branches.

**Primary reference:**
[`eden/.github/workflows/ci.yml`](https://github.com/amdigital-co-uk/eden/blob/main/.github/workflows/ci.yml)
— the fullest current example (three services over a shared domain, on a legacy mixed-TFM
stack). It gets the robustness details right. `qtms-publication` is an earlier, simpler take on
the same shape; prefer eden, and specifically avoid the two mistakes called out under Gotchas
that publication makes.

## The shape

**One `detect-changes` job, then one job group per app,** plus repo-wide security scans and a
single aggregate gate.

### `detect-changes`

Runs `dotnet-affected` once over the solution's project-reference graph and emits a boolean
output per app and per test project, then a second step adds path-diff flags for couplings the
graph cannot see.

- `actions/checkout` with **`fetch-depth: 0`** so the PR base / push-before SHA is reachable.
- Install `dotnet-affected` **pinned to a version** (`--version 6.2.0` in eden) so the affected
  set is deterministic across re-runs of the same commit.
- `BASE_REF` = `${{ github.event.pull_request.base.sha || github.event.before || 'origin/main' }}`
  (PR: the merge target; push: the replaced commit; dispatch: `origin/main`, moot under
  build-all).
- Run: `dotnet affected -p . --solution-path <Sln>.sln --from "$BASE_REF" --to HEAD --format text`.
- **Handle the exit code, do not swallow it** (see Gotchas). `dotnet-affected` exits **166**
  when nothing is affected (legitimate, every gated job should skip); treat any other non-zero
  as a real detection failure and `exit 1`, or a broken detection skips all tests and merges
  green.
- Emit each flag with a **fixed-string** grep so literal dots in `.csproj` names are not treated
  as regex wildcards: `grep -qF "Quartex.X.csproj" affected.txt`.
- A second step uses `git diff --name-only "$BASE_REF" HEAD` for **non-graph couplings**: each
  service's `ContainerEnv/<svc>/` and `ContainerTests/<svc>/` dirs, its Dockerfile, and any
  build-arg or data coupling the `ProjectReference` graph does not express (eden: a `React-Dam`
  build arg, an EF-migrations data project feeding container fixtures).
- Emit a **`shared-build`** flag for truly global files (root shell scripts, `docker-compose.yml`,
  shared assets copied into every image, and `.github/workflows/**` itself) that must force a
  full run.

### Per-app job group

Each app has: test(s) → build (`build-only`) → container test → image security scan. Gate each
on the app's own flags:

```yaml
  build-<app>:
    needs: detect-changes
    if: needs.detect-changes.outputs.<app> == 'true'
       || needs.detect-changes.outputs.<app>-paths == 'true'
       || needs.detect-changes.outputs.shared-build == 'true'
       || inputs.build-all
    uses: amdigital-co-uk/workflows/.github/workflows/docker-build.yml@v2
    with: { mode: build-only, docker-image: "<app-image>", dockerfile: ./<App>/Dockerfile, configure-nuget-feed: true }
    secrets: { PKG_TOKEN: ${{ secrets.PKG_TOKEN }} }
```

The build gate **ORs in the path flag** so a container-test-or-Dockerfile-only change (invisible
to `dotnet-affected`) still builds the image to test against. Test jobs gate on
`<app>-tests || shared-build || build-all`. `dotnet-affected` fans a shared-library change out
to every dependent app and test project automatically; do not hand-maintain a change-to-app map.

An app whose Dockerfile is not self-contained may build via an in-repo reusable
(eden's `build-publish-service.yml`) instead of `docker-build.yml@v2`; the gating is identical.

### Global checks, least privilege

- **CodeQL and checkov run every time, ungated** — security coverage must not depend on which
  app changed.
- Grant `security-events: write` **at job scope** on the SARIF-uploading jobs (codeql, checkov,
  per-app security scans) rather than workflow-wide, keeping every other job's token
  least-privileged.

### The `build-all` escape hatch

A `build-all` boolean, `false` by default on `workflow_call` (CD reuse stays selective) and
`true` on `workflow_dispatch` (a manual run forces everything). Every per-app `if:` ORs in
`|| inputs.build-all`.

### The aggregate required check

Add a final `ci-passed` job with `if: always()` and every job in `needs:`. Mark **this one job**
as the required status check on branch protection, not the individual jobs. A PR whose affected
set skips some jobs still resolves the required check; a failed or cancelled job propagates
through `join(needs.*.result, ' ')`, while a job skipped as unaffected does not fail the gate.
Without this, conditional jobs make branch protection unusable (a required job that skips never
reports).

## `cd.yml` for a multi-app repo

Expose per app both the image tag and the affected flag as `ci.yml` outputs, then in `cd.yml`
reuse `ci.yml` and give each app a tag-and-trigger group gated on its `<app>-affected` output,
so a merge touching one app deploys only that app. See
[`qtms-publication/cd.yml`](https://github.com/amdigital-co-uk/qtms-publication/blob/main/.github/workflows/cd.yml)
for the per-app-gated CD; it pushes to **Azure ACR** where the single-app pubsites example uses
**AWS ECR**, so match the registry inputs to the service's deployment target. Some monorepos
(eden) instead keep image push in a separate `build.yml` on merge and make `ci.yml`
validation-only; confirm which model the repo uses before editing.

## Gotchas

- **Never swallow the detection result.** `... || echo "" ` followed by `exit 0` (as in
  qtms-publication) means a broken `dotnet-affected` run skips every gated job and the PR merges
  green with nothing tested. Branch on the exit code: 166 = nothing affected, other non-zero =
  fail the job.
- **Grep affected projects with `-F`.** Plain `grep -q "Quartex.X.csproj"` treats the dots as
  wildcards and can match the wrong project. Use `grep -qF`.
- **`fetch-depth: 0` is mandatory**; a shallow checkout gives no base to diff against.
- **Container test/env dirs, Dockerfiles, and build-arg/data couplings are invisible to
  `dotnet-affected`.** Cover them with the path-diff step, or those changes never trigger a run.
- **Make the aggregate job the required check**, never the individual conditional jobs.
- **Keep app image names, Dockerfile paths, test-project paths, and folder names consistent**
  across `detect-changes`, the job groups, and `cd.yml`; a typo evaluates to `false` and
  silently disables an app's branch.
- Eden's inline comments document genuinely non-obvious couplings (why a path forces a build,
  why a permission is job-scoped). That is the warranted "why, not what" use of comments; do not
  strip those, and do not pad new workflows with restating comments.
