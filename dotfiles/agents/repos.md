
### Repos (`repos`)

Find local repos from a cached list covering Windows (`/mnt/c/Code`) and WSL native (`~/repos`) roots. On PATH, so it works in non-interactive shells.

```bash
cd "$(repos resolve documents)"  # absolute path; lists candidates if ambiguous, GitHub search if not cloned
repos resolve win:documents      # pick the copy in a specific root (wsl: or win:)
repos find terraform             # absolute paths of every matching copy, no network — use for loops and existence checks
repos ls [term]                  # human-facing list with state (🔒 readonly, 📝 modified, 🌿 branch, ⇄ in both roots)
```

If `resolve` reports multiple matches, re-run with a longer subpath (`repos resolve services/qtms-documents`) rather than adding a step. When a repo is cloned in both roots, `resolve` returns the WSL copy and warns on stderr about the other.

If I mention using "feature branching" workflow/strategy/approach, it means that the current repo has `feature/*` protected. Thus create and push `feature/{name}` off main, then create `work/{name}` off the feature and commit to the work branch, then push and PR targeting the feature branch. Subsequent work should continue pushing fresh work branches off the feature branch, and PRs target the feature branch until such time as the feature branch is ready to merge to main.
