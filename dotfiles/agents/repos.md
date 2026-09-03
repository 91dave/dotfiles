
### Repos (`repos`)

Find local repos from a cached list. On PATH, so it works in non-interactive shells.

```bash
cd "$(repos resolve documents)"  # absolute path; lists candidates if ambiguous, GitHub search if not cloned
repos find terraform             # plain relative paths, no network — use for loops and existence checks
repos ls [term]                  # human-facing list with state (🔒 readonly, 📝 modified, 🌿 branch)
```

If `resolve` reports multiple matches, re-run with a longer subpath (`repos resolve services/qtms-documents`) rather than adding a step.
