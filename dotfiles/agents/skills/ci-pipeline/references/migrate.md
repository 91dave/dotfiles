# Migrate a legacy layout to the unified `ci.yml`

Use when a repo already has CI but not in the current shape: a split `build.yml` + `test.yml`,
a legacy `xunit.yml` job, tests run inside `build.yml`, or reusable workflows pinned
inconsistently. The goal is one `ci.yml` that fans out to the reusable workflows, reused by
`cd.yml`.

## Assess first

Read the existing `.github/workflows`. Identify:

- Where unit tests run today (a `xunit.yml`, a step in `build.yml`, a separate `test.yml`).
- Where the image is built, and whether build and test duplicate checkout/restore/setup.
- Which reusable workflows are already called and at which tag.
- Whether `cd.yml` exists and how it triggers deployment.

## Common migrations

- **Whole-solution xunit gate + hand-maintained per-service `paths:` CIs → unified affected
  detection.** For a monorepo, this is the main migration: replace the split, path-filtered
  workflows with one `ci.yml` whose `detect-changes` job drives per-app gating. Follow
  `references/multi-app.md`; eden's `ci.yml` is a real, merged instance of exactly this move.
- **`xunit.yml` → `dotnet-test.yml`.** Replace the legacy unit-test workflow/job with a
  `dotnet-test.yml@v2` job. Move `dotnet-version` onto it; drop bespoke restore/test steps the
  reusable workflow already does. Update the inputs to the current signature (read
  `dotnet-test.yml` in the workflows repo).
- **Split `build.yml`/`test.yml` → one `ci.yml`.** Create `ci.yml` with the standard jobs
  (`xunit`, `build`, `codeql`, `checkov-scan`, `security-check`, `container-tests`), then make
  the old entrypoint call it: either rename `test.yml` to `ci.yml` and have `build.yml` call
  `ci.yml` via `uses: ./.github/workflows/ci.yml`, or fold `build.yml`'s build into the `build`
  job and delete it. Confirm which the user wants before deleting a file.
- **Tests running inside `build.yml`.** Extract them into the `xunit` job calling
  `dotnet-test.yml`; leave `build` as build-only (`mode: build-only`).
- **Add CodeQL to an existing `ci.yml`.** Add the `codeql` job from the scaffold skeleton. Set
  `dotnet-version` to the repo's framework (the default is `8.0.x`), and set the gate cutoffs
  (`gate-quality`/`gate-security` with `quality-severity-cutoff`/`security-severity-cutoff`)
  rather than leaving analysis ungated.
- **Bump a reusable-workflow tag.** Move all `uses:` lines to a single consistent major tag.
  Read the changelog/inputs of the new tag first; input names and defaults change between
  majors (this is what broke a run in the transcripts).

## Sequence the change safely

1. Pin every `uses:` to the target tag and align inputs to that tag's signature.
2. Introduce `ci.yml` and prove it green on a branch **before** deleting the old workflows, so
   there is no window with no CI.
3. Point `cd.yml` at `ci.yml` (`uses: ./.github/workflows/ci.yml`).
4. Remove the superseded workflow files in the same PR once `ci.yml` is green.

## Verify and record

- Push and confirm the new `ci.yml` run is green with every expected job present.
- This changes the delivery path (C2): **remind the user to update IcePanel** if build or
  deploy behaviour changed.
- Follow the repo's conventional-commit and branch rules; capture what was migrated on the
  backlog item.
