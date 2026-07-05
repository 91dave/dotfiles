---
name: ci-pipeline
description: >
  Set up, migrate, diagnose, or audit an AM service's GitHub Actions CI/CD, built on the
  reusable workflows in amdigital-co-uk/workflows (dotnet-test, docker-build, container-tests,
  codeql, checkov, docker-security-check) wired into a unified ci.yml plus a cd.yml that tags
  a release candidate and triggers the central pipeline. Use when creating ci.yml/cd.yml for a
  repo, migrating a legacy split build.yml/test.yml or xunit.yml layout to the unified ci.yml,
  diagnosing a failing or non-triggering pipeline (docker build failing, "pipeline didn't
  trigger", CodeQL/grype/checkov gates), or checking a repo's workflows against the
  conventions. Modes: new, migrate, diagnose, audit, help.
  Invoke with: /ci-pipeline [new | migrate | diagnose | audit | help]
argument-hint: "[new | migrate | diagnose | audit | help] [repo]"
---

Set up and maintain an AM service's GitHub Actions CI/CD against the shared reusable workflows
in [`amdigital-co-uk/workflows`](https://github.com/amdigital-co-uk/workflows). The house
pattern is a single **`ci.yml`** that fans out to the reusable workflows for the checks, and a
**`cd.yml`** that reruns `ci.yml` on a merged PR, tags a release candidate image, and triggers
the central deployment pipeline.

GitHub is referred to by intent: use whichever GitHub surface is configured (the MCP tools or
`gh`). Do not hardcode a clone path, an org secret value, or a caller's machine.

## Routing

First establish the **mode** (from the argument or intent) and the **target repo**, then load
only that mode's reference file. If neither a mode nor a clear intent is given, show `help` and
stop rather than guessing.

**Target repo defaults to the current repo.** When no repo is named, operate on the repository
in the working directory. Only when a different repo is named does the skill target another one
(resolve it to a local path rather than assuming a location, and `cd` there before acting). If
a repo is named but not checked out locally, say so rather than guessing a path.

| Mode | Trigger signals | Reference |
|---|---|---|
| `new` | "add ci.yml", "set up CI/CD", repo has no `.github/workflows` | `references/scaffold.md` |
| `migrate` | "rename test.yml to ci.yml", "switch xunit.yml for dotnet-test.yml", split `build.yml`/`test.yml`, unify into `ci.yml` | `references/migrate.md` |
| `diagnose` | "docker build failing in CI", "pipeline didn't trigger", a failing run URL, CodeQL/grype/checkov gate failed | `references/diagnose.md` |
| `audit` | "check our workflows", "are we on the current pattern" | this file (see Audit below) |
| `help` | bare invocation, "what can this do" | print Usage and stop |

### Usage

```
/ci-pipeline new [repo]        Scaffold ci.yml + cd.yml against the reusable workflows
/ci-pipeline migrate [repo]    Move a split build/test or xunit.yml layout to a unified ci.yml
/ci-pipeline diagnose [run]    Work out why a run failed or a pipeline did not trigger
/ci-pipeline audit [repo]      Check a repo's workflows against the conventions (read-only)
/ci-pipeline help              Show this usage
```

On a bare invocation with no mode and nothing to infer, print this block and stop.

## The AM CI/CD model

Two workflows per service, both grounded in a real, current example:
[`qtms-redirects/.github/workflows/ci.yml`](https://github.com/amdigital-co-uk/qtms-redirects/blob/main/.github/workflows/ci.yml)
and [`cd.yml`](https://github.com/amdigital-co-uk/qtms-redirects/blob/main/.github/workflows/cd.yml).

**`ci.yml`** runs on every push to a non-`main` branch and is also `workflow_call`-able (so
`cd.yml` can reuse it). It fans out to the reusable workflows as parallel jobs: unit tests,
Docker build, CodeQL, checkov, then image security scan and container tests that depend on the
build. It exposes `tag-used` as an output for `cd.yml` to consume.

**`cd.yml`** runs on a **merged** pull request into `main`, `feature/*`, or `bug/*`. It reuses
`ci.yml`, runs `detect-dotnet-changes` to skip when the target project is untouched, tags the
release-candidate image (`docker-build` in `push-only` mode, pushed to ECR), and, **only when
the base branch is `main`**, triggers the central pipeline via `repository_dispatch` with a
`client_payload` carrying `system`, `app`, `tag`, `digest`, and `actor`. The central pipeline
owns the image deployment.

### Multi-app repos

When a repo builds **more than one deployable image** from one solution, the single-app shape
does not fit: a single `detect-changes` job runs `dotnet-affected` and gates a per-app job group
so only affected apps (and shared-library dependents) run. This applies across `new`, `migrate`,
and `audit`; when the target is a multi-app repo, load `references/multi-app.md`. Primary
example: [`eden`](https://github.com/amdigital-co-uk/eden/blob/main/.github/workflows/ci.yml).

### Optional: in-repo Helm values (emerging, not yet standard)

Some services also keep their Helm values in the repo (`helm/qa-values.yml`,
`helm/live-values.yml`) and apply non-image config themselves, leaving image rollout to the
central pipeline. This pattern is **not fully adopted**; treat it as opt-in and confirm with
the user before scaffolding it. When it applies, load `references/helm-values.md`. Prior art:
[`qtms-am-harvest-api`](https://github.com/amdigital-co-uk/qtms-am-harvest-api/tree/main/.github/workflows).

### Reusable workflow catalogue

Pin to a major tag (current exemplars use `@v2`; `@v3` exists). Signatures below are the inputs
you will actually set; each workflow has more optional inputs.

| Reusable workflow | Purpose | Key inputs | Secrets |
|---|---|---|---|
| `dotnet-test.yml` | Unit tests | `dotnet-version` | `PKG_TOKEN` (required) |
| `docker-build.yml` | Build and/or push the image | `docker-image` (required), `docker-namespace`, `project-name`, `configure-nuget-feed`, `mode` (`build-only` \| `push-only` \| `build-and-push`), `docker-tag`, `tag-as`, `aws-role-arn`, `ecr-region-1/2` | `PKG_TOKEN` |
| `container-tests.yml` | C2 container tests | `docker-compose-file`, `docker-image-name`, `docker-image-namespace`, `docker-image-tag` | — |
| `codeql.yml` | SAST + quality gates | `dotnet-version` (default `8.0.x`), `query-suite`, `gate-quality`, `gate-security`, `quality-severity-cutoff`, `security-severity-cutoff`, `working-directory` | `PKG_TOKEN` (required) |
| `checkov.yml` | IaC/config scan | `skip_checks` | — |
| `docker-security-check.yml` | Grype scan of the built image | `container_registry`, `image_name`, `image_tag` | — |
| `detect-dotnet-changes.yml` | Skip CD when the project is unaffected | `project-path`, `dotnet-version`, `from-ref` | — |

Full input lists live in each reusable workflow's `on.workflow_call.inputs`; read the file in
`amdigital-co-uk/workflows` rather than assuming.

### Conventions that bite

- **CodeQL `dotnet-version` defaults to `8.0.x`.** A service on .NET 10 must set
  `dotnet-version: '10.0.x'` on the `codeql` **and** `dotnet-test` jobs, or the build step
  under analysis fails.
- **Internal NuGet packages need `configure-nuget-feed: true` on `docker-build` and
  `PKG_TOKEN` passed as a secret.** A build that restores `Quartex.*` packages fails without
  both.
- **`ci.yml` ignores pushes to `main`** (`branches-ignore: [main]`); `main` is exercised only
  through `cd.yml` on the merged PR. Do not add a `push: main` trigger to `ci.yml`.
- **The central pipeline only fires for merges whose base is `main`.** A PR merged into a
  `feature/*` or `bug/*` branch runs CI and tags an image but deliberately does not deploy.
- **Keep workflow YAML free of narrating comments.** The self-documenting-code convention
  applies to `.yml` as much as to source: a job named `container-tests` calling
  `container-tests.yml` needs no comment. Add a comment only for a genuinely non-obvious gate
  (for example why a `checkov` check is skipped).

## Audit

To check a repo against the pattern without changing it: confirm a single `ci.yml` exists (not
a split `build.yml`/`test.yml` or a legacy `xunit.yml`); it calls the reusable workflows at a
consistent pinned tag; unit tests, build, CodeQL, checkov, image security scan, and container
tests are all present (or their absence is deliberate and noted); `dotnet-version` is
consistent and correct for the target framework; and `cd.yml` gates deployment on
`detect-dotnet-changes` and `base_ref == 'main'`. Report gaps against this list; do not edit in
audit mode.

## Verification

- Push the branch and confirm the `ci.yml` run is green, with every expected job present and
  none silently skipped.
- For CD changes, confirm on a merged PR that `detect-dotnet-changes` resolves correctly and,
  for a `main` merge, that `trigger-pipeline` dispatched (check the run's step summary and the
  central pipeline repo).
- Follow the repo's contributing rules for the change itself (conventional commit referencing
  the backlog item, no direct commits to `main`).

## Prior art

- **[`qtms-redirects`](https://github.com/amdigital-co-uk/qtms-redirects/tree/main/.github/workflows)**
  — the canonical current layout: unified `ci.yml`, `cd.yml`, and `detect-dotnet-changes.yml`.
  Use it as the reference when scaffolding or migrating.
- **[`amdigital-co-uk/workflows`](https://github.com/amdigital-co-uk/workflows/tree/main/.github/workflows)**
  — the reusable workflows themselves; read the input definitions here.
