# Dotfiles Library Documentation

Comprehensive documentation for all helper functions and aliases in `/dotfiles/lib`.

- [AWS Helpers](aws.md)
- [Development Helpers](dev.md)`
- [Git & Worktree Management](git.md)
- [Kubernetes Helpers](kubernetes.md)
- [Telepresence Helpers](telepresence.md)
- [Terraform Helpers](terraform.md)
- [Todo List](todo.md)
- [WSL Integration Helpers](wsl.md)

## Common Workflows

### Daily WIP Overview

Use this workflow at the start of your day to get a quick overview of work in progress across all repositories and ensure you have the latest changes.

```bash
# One-command daily refresh: fetch + clear merged branches + status
repos reset

# Or run individual steps:
repos fetch    # Fetch updates from all repositories
repos ls       # View repos with uncommitted changes or off main branch

# Open a specific repo
repos code my-repo      # VS Code
repos claude my-repo    # Claude Code
repos cd my-repo        # pushd into the repo
repos cmd my-repo       # WSL window
```

### Multi-Repo Feature Development

Use this workflow when implementing the same feature or fix across multiple repositories, allowing you to compare implementations and maintain consistency.

```bash
# Create worktrees for multiple repos using a consistent branch name
gwt add api-service feature/add-logging
gwt add web-app feature/add-logging
gwt add mobile-app feature/add-logging

# Or use group add to create all at once (requires repos-groups.cfg)
gwt gadd platform feature/add-logging

# Open VS Code or Claude with context of all worktrees
gwt code
# or
gwt claude
```

### Workspace Management

Use workspaces for multi-repo projects or custom directory setups that aren't tied to a single git repo.

```bash
# Navigate to a workspace
gws cd my-project

# Open a workspace in Claude Code or VS Code
gws claude my-project
gws edit my-project
```

### Parallel Work in Same Repo

Use this workflow when juggling multiple tasks in the same repository simultaneously, such as working on a feature while addressing urgent bug fixes.

```bash
# Create multiple worktrees in different branches and open separate editor instances
gwt code my-repo -b feature/new-dashboard
gwt code my-repo -b hotfix/critical-bug
gwt claude my-repo -b feature/api-refactor
```



