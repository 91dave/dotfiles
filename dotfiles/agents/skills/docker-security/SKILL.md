---
name: docker-security
description: >
  Harden a service's Dockerfile and clear container-image vulnerabilities: run the image as a
  non-root user, upgrade OS packages, then build the image and scan it locally with Grype,
  reporting the fixable findings and a suggested set of dependency version pins. Use when
  hardening a Dockerfile, responding to a container security scan (Grype / Trivy / Dependabot),
  prepping an image for release, or after a base-image or framework upgrade.
  Invoke with: /docker-security [image-tag]
argument-hint: "[image-tag]"
---

Harden a container image and clear its fixable vulnerabilities. Three phases: harden the
Dockerfile, scan the built image with Grype, then propose dependency pins for the fixable
findings. To only scan an existing image, skip to Phase 2.

Container engine and scanner are referred to by intent: use whichever `docker`/`podman` and
`grype` are on the machine. Do not hardcode an engine, a platform, or a username.

## When to use

- Hardening a `Dockerfile` (non-root user, OS-package upgrade).
- Responding to a container scan (Grype/Trivy in CI, Dependabot) flagging image CVEs.
- After a base-image bump or framework upgrade, to confirm the new image is clean.

## Phase 1 — Harden the Dockerfile (runtime stage)

### Run as a non-root user

Containers should not run as root. Add a dedicated unprivileged user in the **runtime** stage,
own the app directory to it, and switch with `USER` as the last instruction. Pick a neutral
name — derive it from the service, or use a generic one like `appuser`.
Debian/Ubuntu-based images:

```dockerfile
RUN groupadd -r appuser && useradd -r -g appuser appuser \
    && chown -R appuser:appuser /app
USER appuser
```

Alpine-based images:

```dockerfile
RUN addgroup -S appuser && adduser -S -G appuser appuser \
    && chown -R appuser:appuser /app
USER appuser
```

Note: some modern base images already ship a non-root user (for example the .NET
`aspnet:8.0`+ images include `app`), in which case a bare `USER app` is enough. Either way,
do not leave the final image running as root.

### Upgrade OS packages (and install only what is needed)

Refresh OS packages in the runtime stage to clear base-image CVEs, in a single cleaned layer:

```dockerfile
# Debian/Ubuntu
RUN apt-get update \
    && apt-get upgrade -y \
    && apt-get install -y --no-install-recommends <packages> \
    && rm -rf /var/lib/apt/lists/*
```

```dockerfile
# Alpine
RUN apk update && apk upgrade && apk add --no-cache <packages>
```

Gotchas:

- **Minimal runtime images often ship neither `curl` nor `wget`.** If the container's
  `HEALTHCHECK` (or a Compose healthcheck) shells out to `curl`, it will never pass and the
  container is reported unhealthy — which fails `docker compose up --wait` and any
  `depends_on: condition: service_healthy`. If a healthcheck needs `curl`, install it. (Seen
  for real: a service stuck unhealthy under `--wait` purely because the base image had no curl;
  it was masked locally by `up -d` + polling the health endpoint from the host.)
- **Install only what the runtime needs** — every added package is attack surface.
- Keep the upgrade/install in one `RUN` so it is one cleanable layer, and `chown` after the
  app is copied in.

## Phase 2 — Build and scan with Grype

1. **Build the image** with the local container engine:

   ```bash
   <engine> build . -t <image>:<tag> [--build-arg ...]
   ```

2. **Scan it, fixable findings only.** `--only-fixed` keeps the report to vulnerabilities you
   can actually act on; a severity floor matches typical CI gating:

   ```bash
   grype <image>:<tag> --only-fixed --fail-on medium -o table
   ```

   (If `grype` is not installed: https://github.com/anchore/grype#installation.)

3. **Get machine-readable output** for the pin analysis in Phase 3:

   ```bash
   grype <image>:<tag> --only-fixed -o json > grype.json
   ```

## Phase 3 — Triage fixable findings and suggest pins

Split fixable findings into OS packages and application dependencies — they are fixed by
different means.

**Application-dependency findings → candidate version pins.** One line per
`type / name / current → fix version / advisory / severity`:

```bash
jq -r '.matches[]
  | select(.vulnerability.fix.state=="fixed")
  | select(.artifact.type | test("^(deb|apk|rpm)$") | not)
  | "\(.artifact.type)\t\(.artifact.name)\t\(.artifact.version) -> \(.vulnerability.fix.versions|join(","))\t\(.vulnerability.id)\t\(.vulnerability.severity)"' \
  grype.json | sort -u
```

**OS-package findings → not pins.** These are cleared by the Phase 1 OS upgrade or by
refreshing the base image, never by dependency pins:

```bash
jq -r '.matches[]
  | select(.vulnerability.fix.state=="fixed")
  | select(.artifact.type | test("^(deb|apk|rpm)$"))
  | "\(.artifact.name)\t\(.artifact.version)\t\(.vulnerability.id)\t\(.vulnerability.severity)"' \
  grype.json | sort -u
```

Then present a suggested pin per application dependency: **the highest fix version offered
across that package's fixable advisories**, so one pin clears them all.

### Applying pins by ecosystem

- **.NET with Central Package Management** — add a `<PackageVersion>` in
  `Directory.Packages.props`. If the package is only a *transitive* dependency and
  `CentralPackageTransitivePinningEnabled` is `false`, also add a direct `<PackageReference>`
  in the project, or the pin has no effect.
- **npm** — `overrides`; **yarn** — `resolutions`; **Python** — a constraint/pin; **Maven** —
  `dependencyManagement`.

### Gotchas when pinning

- **A pin can force a higher transitive than its own advisory floor.** The patched package may
  itself depend on a newer version of another package than that other package's fix version.
  Pin to the **higher** of (the advisory's fix version, the dependency's minimum). Seen for
  real: `AWSSDK.Extensions.CloudFront.Signers 4.0.0.26` required `AWSSDK.Core >= 4.0.3.15`,
  above Core's own advisory fix of `4.0.3.3` — so Core had to be pinned to `4.0.3.15`.
- **Framework false positives.** Scanners read `deps.json`/lock files and can flag shared
  framework assemblies (pinned at a constant version) even when the installed runtime is
  patched. These do not clear by pinning — suppress/dismiss them rather than chasing a pin.
- **Re-scan after pinning.** Rebuild the image and re-run the Grype scan to confirm each
  finding clears, and confirm the build (and tests) still pass.

## Verification

- `grype <image>:<tag> --only-fixed --fail-on medium` exits 0 (no fixable findings at or above
  the floor remain), with any residual entries being known false positives.
- The image runs as a non-root user (`<engine> run --rm --entrypoint sh <image>:<tag> -c id`
  shows a non-zero uid).
- Any healthcheck the image/Compose defines actually passes (`<engine> compose up --wait`
  succeeds where applicable).

## Prior art

- **qtms-redirects PR #62** — non-root user restored, `apt-get upgrade` + `curl` install in the
  runtime stage, and AWS SDK security pins, during a .NET 10 upgrade.
- **qtms-metadata PR #203** — OS-package upgrade in the runtime image to clear `libgnutls30t64`
  CVEs.
- **qtms-metadata PR #204** — pinning transitively-pulled framework packages to patched
  versions via a `PackageVersion` plus a direct `PackageReference` under CPM.
