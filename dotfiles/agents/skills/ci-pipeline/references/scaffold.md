# Scaffold `ci.yml` and `cd.yml` for a service

Use when a repo has no CI/CD, or only ad-hoc workflows. Copy the shape from
[`qtms-redirects`](https://github.com/amdigital-co-uk/qtms-redirects/tree/main/.github/workflows)
and adapt the names. Do not invent inputs; read the reusable workflow in
`amdigital-co-uk/workflows` when unsure.

**If the repo builds more than one deployable image from one solution, stop and use
`references/multi-app.md` instead** — this single-app shape does not fit a monorepo.

## What you need first

- The service's **image name** (kebab, e.g. `redirects-service`) and **namespace** (usually
  `qtms`).
- The **main project** path (`Quartex.X/Quartex.X.csproj`) for `detect-dotnet-changes`.
- The **target framework** so `dotnet-version` is right on the `dotnet-test` and `codeql` jobs.
- Whether the build restores internal `Quartex.*` packages (then `configure-nuget-feed: true`
  and pass `PKG_TOKEN`).
- Whether the repo has a `ContainerEnv` with a compose file for container tests.
- Confirmation of the pinned reusable-workflow tag (match the exemplar, currently `@v2`).

## `ci.yml` skeleton

Trigger on non-`main` pushes and expose it as `workflow_call` so `cd.yml` can reuse it.

```yaml
name: CI Pipeline
permissions:
  id-token: write
  contents: read
  actions: read
  packages: read
  security-events: write
on:
  workflow_call:
    secrets:
      PKG_TOKEN: { required: true }
    outputs:
      tag-used: { value: ${{ jobs.build.outputs.tag-used }} }
  push:
    branches-ignore: [main]
jobs:
  xunit:
    uses: amdigital-co-uk/workflows/.github/workflows/dotnet-test.yml@v2
    with: { dotnet-version: "10.0.x" }
    secrets: { PKG_TOKEN: ${{ secrets.PKG_TOKEN }} }
  build:
    uses: amdigital-co-uk/workflows/.github/workflows/docker-build.yml@v2
    with:
      docker-image: "<image-name>"
      docker-namespace: ""
      configure-nuget-feed: true
      project-name: <Quartex.X>
      mode: build-only
    secrets: { PKG_TOKEN: ${{ secrets.PKG_TOKEN }} }
  codeql:
    uses: amdigital-co-uk/workflows/.github/workflows/codeql.yml@v2
    with:
      query-suite: security-and-quality
      gate-quality: true
      gate-security: true
      quality-severity-cutoff: error
      security-severity-cutoff: high
      dotnet-version: '10.0.x'
    secrets: { PKG_TOKEN: ${{ secrets.PKG_TOKEN }} }
  checkov-scan:
    uses: amdigital-co-uk/workflows/.github/workflows/checkov.yml@v2
    with: { skip_checks: CKV_GHA_7 }
  security-check:
    needs: [build]
    uses: amdigital-co-uk/workflows/.github/workflows/docker-security-check.yml@v2
    with:
      container_registry: "temp"
      image_name: "<image-name>"
      image_tag: ${{ needs.build.outputs.tag-used }}
  container-tests:
    needs: build
    uses: amdigital-co-uk/workflows/.github/workflows/container-tests.yml@v2
    with:
      docker-compose-file: ContainerEnv/docker-compose.integration.yml
      docker-image-namespace: "temp"
      docker-image-name: "<image-name>"
      docker-image-tag: "${{ needs.build.outputs.tag-used }}"
```

Drop the `container-tests` job if the repo has no `ContainerEnv`; note the omission on the work
item rather than leaving a broken job.

## `cd.yml` skeleton

Runs on merged PRs, reuses `ci.yml`, tags the release candidate, triggers the central pipeline
only for `main`. Mirror
[`qtms-redirects/cd.yml`](https://github.com/amdigital-co-uk/qtms-redirects/blob/main/.github/workflows/cd.yml):
the `ci`, `detect-changes`, `get-ecr-config`, `tag-release-candidate`, and `trigger-pipeline`
jobs. Set `docker-namespace: qtms`, the ECR regions (`us-east-1`, `us-east-2`),
`aws-role-arn: ${{ vars.PIPELINE_ECR_ARN }}`, `mode: push-only`, and `SYSTEM: quartex-pubsites`
in `trigger-pipeline` (or the correct system for the service).

`detect-dotnet-changes` can be a local workflow (as in `qtms-redirects`) or the shared
`amdigital-co-uk/workflows/.github/workflows/detect-dotnet-changes.yml@v2` (as in
`qtms-am-harvest-api`). Prefer the shared one for new work.

## Repo and pipeline configuration (outside the workflow files)

- **Secrets/vars**: `PKG_TOKEN` and `CD_TOKEN` secrets; `PIPELINE_ECR_ARN`, `CD_TRIGGER_REPO`,
  `CD_TRIGGER_EVENT`, `CD_LINK_MONITOR`, `CD_LINK_HELP` vars must exist on the repo or org.
- **Central pipeline**: the system (e.g. `quartex-pubsites`) must be registered in `am-pipeline`
  and, where relevant, `am-deploy-manifests`, or `trigger-pipeline` dispatches to nothing.
  Remind the user to make the `am-pipeline` change as a follow-up.

## Reminders

- This is a C2-level change to the delivery path. **Remind the user to update IcePanel** if it
  alters how the container is built, deployed, or what it depends on.
- Keep the YAML comment-free beyond genuinely non-obvious gates.
- Commit per the repo's conventional-commit rules, referencing the backlog item; do not push to
  `main`.
