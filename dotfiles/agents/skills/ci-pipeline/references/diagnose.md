# Diagnose a failing or non-triggering pipeline

Use when a run failed, a gate blocked a merge, or an expected run never started. Get the run
first, then match the symptom below. Fetch the failing run and its logs by intent (the GitHub
MCP tools or `gh run view <id> --log-failed`); read the actual failing step before theorising.

## "The pipeline didn't trigger"

Almost always the trigger conditions, not a bug. Check in order:

- **`ci.yml` ignores `main`** (`branches-ignore: [main]`). A push to `main` runs no CI directly;
  `main` is exercised via `cd.yml` on the merged PR. Expected, not a fault.
- **`cd.yml` runs only on a merged PR** into `main`/`feature/*`/`bug/*`
  (`pull_request: types: [closed]` + `if: github.event.pull_request.merged == true`). A direct
  push, or a closed-without-merge PR, does nothing.
- **The central pipeline fires only for `main`.** `trigger-pipeline` is gated on
  `github.base_ref == 'main'`. Merges into `feature/*` or `bug/*` build and tag an image but do
  not deploy, by design.
- **`detect-dotnet-changes` returned `has-changes=false`.** The downstream tag/deploy jobs are
  `if: needs.detect-changes.outputs.has-changes == 'true'`, so an untouched target project
  skips them. Check `project-path` and `from-ref` are right.
- **Helm values callers** trigger only on a `push` to `main` touching the exact
  `paths:` file. A values change on a branch, or a path mismatch, triggers nothing.

## "Docker build failing in CI"

- **Internal package restore fails** (`Quartex.*` not found / 401). Needs
  `configure-nuget-feed: true` on the `docker-build` job **and** `PKG_TOKEN` passed as a secret.
  Check both are present and the token is valid.
- **Wrong `project-name` / `dockerfile` / `working-directory`.** Confirm they match the repo.
- **Tag/mode mismatch between CI and CD.** CI builds `mode: build-only`; CD pushes
  `mode: push-only` using `docker-tag: ${{ needs.ci.outputs.tag-used }}`. A missing `tag-used`
  output on `ci.yml` breaks the CD push.
- Read the failing step's log; a compile error is a code problem, not a workflow one.

## CodeQL gate failed

- **Build step under analysis fails** because `dotnet-version` is wrong. The default is
  `8.0.x`; a .NET 10 service must set `dotnet-version: '10.0.x'`.
- **A real finding at or above the cutoff.** With `gate-security`/`gate-security-cutoff` set,
  the job fails the merge. Triage the alert; do not lower the cutoff to get green.
- Confirm `working-directory` points at the solution/project being analysed.

## Grype / `docker-security-check` findings

Fixable image CVEs at or above the floor. Hand off to the **`docker-security`** skill to harden
the Dockerfile (non-root user, OS upgrade) and propose dependency pins; do not suppress
findings to pass the gate.

## Checkov gate failed

An IaC/config check tripped. Fix the flagged config where legitimate; only add the check id to
`skip_checks` when the exception is justified, and note why.

## Common mechanical causes

- **Missing repo/org secret or var**: `PKG_TOKEN`, `CD_TOKEN`, `PIPELINE_ECR_ARN`,
  `CD_TRIGGER_REPO`, `CD_TRIGGER_EVENT`. An empty `CD_TRIGGER_REPO` makes `trigger-pipeline`
  dispatch to nothing silently.
- **Reusable-workflow input drift after a tag bump.** A renamed or newly required input on the
  new major tag fails the call. Read that tag's `on.workflow_call.inputs`.
- **Missing `permissions`** on a caller job (notably `id-token: write`, `packages: read`,
  `security-events: write`) surfaces as auth or upload failures.

## After fixing

Re-run and confirm green. If the fix changed build or deploy behaviour, **remind the user to
update IcePanel**. If it was a live-incident hotfix, note the follow-up to backfill any missing
test/regression coverage per the repo's rules.
