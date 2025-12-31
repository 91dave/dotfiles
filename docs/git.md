# Git & Worktree Management

Opinionated helpers for managing multiple git repositories and git worktrees in a Windows/WSL2 environment.

## Configuration

```bash
# Windows paths
REPO_HOME_WIN='C:\Code'
WORKTREE_HOME_WIN='C:\Code\workspace'

# Converted WSL paths (automatically set)
REPO_HOME=$(wslpath $REPO_HOME_WIN)
WORKTREE_HOME=$(wslpath $WORKTREE_HOME_WIN)

# Repository cache file
REPO_CACHE=$REPO_HOME/repos-cache.lst
```

## Repository Management

### is_repo

Checks if the current directory is a git repository.

```bash
is_repo
```

**Returns:**
- `true` if current directory is a git repo
- `false` otherwise

**Example:**
```bash
if [ "$(is_repo)" = "true" ]; then
    echo "This is a git repository"
fi
```

### find_git_repos

Recursively finds all git repositories within a folder.

```bash
find_git_repos [folder] [max_depth]
```

**Parameters:**
- `folder` - Directory to search (default: current directory)
- `max_depth` - Maximum depth to search (default: 3)

**Example:**
```bash
# Find repos in C:\Code with depth 4
find_git_repos "/mnt/c/Code" 4

# Find repos in current directory
find_git_repos
```

### update_repo_cache

Scans for repositories and updates the cache file.

```bash
update_repo_cache
```

**Example:**
```bash
update_repo_cache
# Output:
# 🔍 Scanning for repos in /mnt/c/Code...
# ✅ Found 23 repos, cache updated
```

**Note:** The cache file excludes folders with `_backup` or `.bak` in the name.

### fetch_repos

Fetches updates for all cached repositories and auto-pulls when safe.

```bash
fetch_repos
```

**How it works:**
1. Reads repositories from the cache file
2. For each repository:
   - Fetches from origin (tries `main`, then `master`)
   - Counts new commits
   - Auto-pulls if:
     - Current branch is `main` or `master`
     - Working directory is clean (no uncommitted changes)
   - Otherwise, displays why pull was skipped

**Example output:**
```
🔄 myapp
   📥 3 new commit(s)
   ✅ Pulled
🔄 another-project
   📥 1 new commit(s)
   ⏭️  Skipped pull (on feature-branch)
🔄 work-in-progress
   ⏭️  Skipped pull (uncommitted changes)
```

## Git Worktree Management

Git worktrees allow you to have multiple working directories for a single repository, making it easy to work on multiple branches simultaneously.

### gwt_usage

Displays usage information for git worktree commands.

```bash
gwt_usage
```

### gwt

Main command for managing git worktrees.

```bash
gwt [cmd] [branch]
gwt [cmd] [repo] [branch]
```

**Commands:**

#### List current worktrees
```bash
gwt
```
Shows all worktrees for the current repository.

#### List all worktrees in workspace
```bash
gwt ls
```
Shows all worktrees across all repositories in your workspace.

**Example output:**
```
📂 Worktrees in /mnt/c/Code/workspace:
  📁 myapp-feature-123
     └─ 🔗 myapp  🌿 feature/ticket-123
  📁 myapp-hotfix
     └─ 🔗 myapp  🌿 hotfix/critical-bug
```

#### Create worktree
```bash
gwt add [branch]
```
Creates a new worktree for the specified branch.

**Example:**
```bash
# From within a repository
cd /mnt/c/Code/myapp
gwt add feature/new-feature

# Creates: /mnt/c/Code/workspace/myapp-new-feature
```

**With repository search:**
```bash
# From anywhere
gwt add myapp feature/new-feature
```

#### Remove worktree
```bash
gwt rm [branch]
```
Deletes the specified worktree.

**Example:**
```bash
# From within a repository
gwt rm feature/old-feature

# From anywhere (with repo search)
gwt rm myapp old-feature
```

#### Create and open in VS Code
```bash
gwt code [branch]
```
Creates a worktree and immediately opens it in VS Code.

**Example:**
```bash
gwt code feature/new-ui
# Creates worktree and runs: code /mnt/c/Code/workspace/myapp-new-ui
```

#### Create and open in Claude Code
```bash
gwt claude [branch]
```
Creates a worktree and immediately opens it in Claude Code.

**Example:**
```bash
gwt claude feature/refactor-api
# Creates worktree and runs: claude /mnt/c/Code/workspace/myapp-refactor-api
```

### gwt_clear

Removes all worktrees from the workspace directory.

```bash
gwt_clear
```

**Example:**
```bash
gwt_clear
# Output:
# 🗑️  Found 5 folder(s) in /mnt/c/Code/workspace:
# myapp-feature-1
# myapp-feature-2
# other-feature
#
# Remove all worktrees? [y/N] y
# 🔄 Processing: myapp-feature-1
#   ✅ Removing from: myapp
```

**Safety features:**
- Prompts for confirmation before removing
- Only removes valid git worktrees
- Skips non-worktree directories

## Worktree Naming Convention

Worktrees are automatically named based on the repository and branch:

```
{project}-{tag}
```

Where:
- `project` is the repository name (shortened if it contains hyphens)
- `tag` is the last component of the branch name

**Examples:**
- Repo: `myapp`, Branch: `feature/new-ui` → Worktree: `myapp-new-ui`
- Repo: `company-myapp`, Branch: `hotfix/bug-123` → Worktree: `myapp-bug-123`

## Workflow Examples

### Multi-feature development
```bash
# Start work on two features simultaneously
cd /mnt/c/Code/myapp
gwt add feature/user-auth
gwt add feature/admin-panel

# Work in both
cd /mnt/c/Code/workspace/myapp-user-auth
# ... make changes ...

cd /mnt/c/Code/workspace/myapp-admin-panel
# ... make changes ...
```

### Quick PR review
```bash
# Create worktree, open in editor
gwt code pr/review-changes

# When done reviewing
gwt rm pr/review-changes
```

### Maintenance workflow
```bash
# Update repository cache weekly
update_repo_cache

# Fetch all repos daily
fetch_repos

# Clean up old worktrees
gwt ls  # Review what's there
gwt_clear  # Remove all if needed
```

## Usage Tips

1. **Repository Cache**: Run `update_repo_cache` after adding new repositories
2. **Daily Updates**: Add `fetch_repos` to your startup script for automatic updates
3. **Worktree Cleanup**: Periodically run `gwt ls` to review and `gwt_clear` to clean up
4. **Branch Search**: When using `gwt add [repo] [branch]`, only one matching repo should exist
5. **Quick Access**: Use `gwt code` or `gwt claude` for immediate editor integration
