# Dotfiles Library Documentation

Comprehensive documentation for all helper functions and aliases in `/dotfiles/lib`.

- [AWS Helpers](aws.md)
- [Development Helpers](dev.md)`
- [Git & Worktree Management](git.md)
- [Kubernetes Helpers](kubernetes.md)
- [Telepresence Helpers](telepresence.md)
- [Terraform Helpers](terraform.md)
- [WSL Integration Helpers](wsl.md)

## Common Workflows

### Daily WIP Overview

Use this workflow at the start of your day to get a quick overview of work in progress across all repositories and ensure you have the latest changes.

```bash
# Fetch updates from all repositories
repos fetch

# View repositories with uncommitted changes or off main branch
repos ls

# Open a specific repo in VS Code
repos code my-repo

# Open a specific repo in CMD window
repos cmd my-repo
```

### Multi-Repo Feature Development

Use this workflow when implementing the same feature or fix across multiple repositories, allowing you to compare implementations and maintain consistency.

```bash
# Create worktrees for multiple repos using a consistent branch name
gwt add api-service feature/add-logging
gwt add web-app feature/add-logging
gwt add mobile-app feature/add-logging

# Open VS Code or Claude with context of all worktrees
gwt code
# or
gwt claude
```

### Parallel Work in Same Repo

Use this workflow when juggling multiple tasks in the same repository simultaneously, such as working on a feature while addressing urgent bug fixes.

```bash
# Create multiple worktrees in different branches and open separate editor instances
gwt code my-repo -b feature/new-dashboard
gwt code my-repo -b hotfix/critical-bug
gwt claude my-repo -b feature/api-refactor
```



