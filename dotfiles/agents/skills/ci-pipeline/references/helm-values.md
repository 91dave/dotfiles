# In-repo Helm values (emerging pattern)

**Not yet standard.** Confirm with the user before adopting it for a service. Prior art:
[`qtms-am-harvest-api`](https://github.com/amdigital-co-uk/qtms-am-harvest-api/tree/main/.github/workflows).

## The idea

Ownership of a deployment is split:

- **Image rollout** stays with the central pipeline (`cd.yml` tags the release candidate and
  dispatches to the pipeline). The pipeline owns `image.tag`.
- **Everything else in the Helm values** (resources, probes, strategy, affinity, tolerations,
  node selectors) lives **in the repo** under `helm/<env>-values.yml` and is applied by a
  workflow when that file changes.

The apply step reads the currently-deployed `image.tag` (`helm get values`) and re-applies it
with `--set image.tag=...`, so a values-only change never rolls the running image back. On a
first install it falls back to the tag written in the values file.

## Target shape: shared reusable + thin per-environment callers

Assume the reused apply workflow lives in the shared
[`amdigital-co-uk/workflows`](https://github.com/amdigital-co-uk/workflows) repo (today it sits
locally in `qtms-am-harvest-api` as `helm-deploy-values.yml`; the intent is to promote it).
Scaffold the callers against the shared copy, not a local one:

```yaml
# .github/workflows/deploy-qa-values.yml
name: Deploy QA values
on:
  push:
    branches: [main]
    paths: [helm/qa-values.yml]
  workflow_dispatch:
permissions:
  id-token: write
  contents: read
jobs:
  deploy:
    uses: amdigital-co-uk/workflows/.github/workflows/helm-deploy-values.yml@v2
    with:
      cluster: quartex-development
      namespace: qa
      helm-chart: quartex-webapp
      service-name: <service-name>
      values-file: helm/qa-values.yml
      aws-role-arn: ${{ vars.PIPELINE_ECR_ARN }}
```

Add a `deploy-live-values.yml` caller with `namespace: live`, the live cluster, and
`paths: [helm/live-values.yml]`. One caller per environment, each triggered only by a change to
its own values file (plus `workflow_dispatch`).

If the shared `helm-deploy-values.yml` does not yet exist in the workflows repo, promoting it
there is the first step; only fall back to a local copy if the user explicitly wants to keep it
in-repo for now.

## The reusable apply workflow (inputs it must expose)

`cluster`, `namespace`, `helm-chart` (e.g. `quartex-webapp`), `service-name` (the Helm release),
`values-file`, `aws-role-arn` (required), plus optional `helm-repo`
(default `s3://quartex-helm-charts/stable/`), `aws-region`, `chart-version`, `upgrade-timeout`.
Its job assumes an OIDC role, configures EKS access, adds the S3 Helm repo, preserves the
running image tag, then `helm upgrade --install --wait`.

## Gotchas

- **Tag preservation is the whole point.** If the apply step ever stops re-setting the
  deployed `image.tag`, a config-only change silently redeploys whatever tag is in the values
  file. Keep the preserve step.
- **Path filters must match the values files exactly**, or a values change deploys nothing (or
  the wrong environment deploys).
- The values files reference the ECR image repository directly; keep that in step with the
  namespace/image the central pipeline pushes to.
