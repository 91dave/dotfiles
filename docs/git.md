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

### repos

Multi-purpose command for managing all repositories in the cache.

```bash
repos [subcommand]
# or
repo [subcommand]  # alias
```

**Subcommands:**

#### repos cache

Scans for repositories and updates the cache file.

```bash
repos cache
```

**Example:**
```bash
repos cache
# Output:
# 🔍 Scanning for repos in /mnt/c/Code...
# ✅ Found 23 repos, cache updated
```

**Note:** The cache file excludes folders with `_backup` or `.bak` in the name.

#### repos fetch

Fetches updates for all cached repositories and auto-pulls when safe.

```bash
repos fetch
```

**How it works:**
1. Reads repositories from the cache file
2. For each repository:
   - Fetches from origin (tries `main`, then `master`)
   - Counts new commits (skips repos with no new commits)
   - Auto-pulls if:
     - Current branch is `main` or `master`
     - Working directory is clean (no uncommitted changes)
   - Otherwise, categorizes why pull was skipped
3. Provides summary of skipped repos grouped by reason

**Example output:**
```
🔄 myapp
   📥 3 new commit(s)
   ✅ Pulled
🔄 another-project
   📥 1 new commit(s)

⏭️  Skipped pull for 2 repo(s):

   Uncommitted changes:
      work-in-progress

   Different branch:
      another-project (feature-branch)
```

#### repos status

Checks status of all cached repositories.

```bash
repos status
```

**Shows:**
- Repos not on main/master branch
- Repos with uncommitted changes
- Merge status indicators for branches (whether commits are merged into main)

**Example output:**
```
🔍 Checking repo status...

🌿 Not on main (2):
   📁 myapp (feature-branch) ✅ merged
   📁 another-project (hotfix) ⚠️ 3 unmerged commit(s)

✏️  Uncommitted changes (1):
   📁 work-in-progress (main, 3 file(s))
```

#### repos main

Switches all repositories to their main branch (main or master).

```bash
repos main
```

**Safety features:**
- Only switches repos not currently on main
- Skips repos with uncommitted changes
- Skips repos with unmerged commits
- Shows summary of switched and skipped repos

**Example output:**
```
🔄 Switching repos to main branch...

✅ myapp: feature-branch → main
✅ another-project: develop → main

✅ Switched 2 repo(s) to main

⏭️  Skipped 2 repo(s):

   Uncommitted changes:
      work-in-progress (feature-x)

   Unmerged commits:
      new-feature (feature-y, 3 commit(s))
```

#### repos clear

Deletes all branches that have been merged into main/master.

```bash
repos clear
```

**Safety features:**
- Never deletes main, master, or current branch
- Only deletes branches fully merged

**Example output:**
```
🗑️  Deleting merged branches...

📁 myapp
   ✅ Deleted: feature/old-feature
   ✅ Deleted: hotfix/bug-123

📁 another-project
   ✅ Deleted: feature/completed

✅ Deleted 3 branch(es)
```

#### repos help

Displays help information for the repos command.

```bash
repos help
```

#### repos code

Opens VS Code in a matching repository.

```bash
repos code [search]
```

**Parameters:**
- `search` - Repository name or partial match

**Example:**
```bash
repos code myapp
# Opens VS Code in the matching repository
```

#### repos cmd

Opens a CMD window in a matching repository.

```bash
repos cmd [search]
```

**Parameters:**
- `search` - Repository name or partial match

**Example:**
```bash
repos cmd myapp
# Opens CMD in the matching repository
```

## Git Worktree Management

Git worktrees allow you to have multiple working directories for a single repository, making it easy to work on multiple branches simultaneously.

### gwt_usage

Displays usage information for git worktree commands.

```bash
gwt_usage
# or
gwt help
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
gwt add [branch]           # Tagless (uses repo name as folder)
gwt add -b [branch]        # Tagged (uses repo-branch as folder)
```
Creates a new worktree for the specified branch.

**Folder naming:**
- Without `-b`: Uses repo name only (e.g., `myapp`)
- With `-b`: Uses repo-branch format (e.g., `myapp-new-feature`)
- If folder exists, automatically uses tagged format

**Auto-switching:**
If the main repo is currently on the branch you're creating a worktree for (with uncommitted changes), the command will fail and ask you to commit or stash first. If clean, it auto-switches the main repo to main/master.

**Example:**
```bash
# From within a repository
cd /mnt/c/Code/myapp
gwt add feature/new-feature
# Creates: /mnt/c/Code/workspace/myapp

gwt add -b feature/another-feature
# Creates: /mnt/c/Code/workspace/myapp-another-feature
```

**With repository search:**
```bash
# From anywhere
gwt add myapp feature/new-feature
gwt add myapp -b feature/another-feature
```

#### Remove worktree
```bash
gwt rm              # Remove tagless worktree (repo name folder)
gwt rm [branch]     # Remove tagged worktree (repo-branch folder)
```
Deletes the specified worktree.

**Example:**
```bash
# From within a repository
gwt rm                    # Removes /workspace/myapp
gwt rm feature/old-feature  # Removes /workspace/myapp-old-feature

# From anywhere (with repo search)
gwt rm myapp             # Removes tagless worktree
gwt rm myapp old-feature # Removes tagged worktree
```

#### Create and open in VS Code
```bash
gwt code [branch]           # Tagless
gwt code -b [branch]        # Tagged
```
Creates a worktree and immediately opens it in VS Code.

**Example:**
```bash
gwt code feature/new-ui
# Creates worktree and runs: code /mnt/c/Code/workspace/myapp

gwt code -b feature/new-ui
# Creates worktree and runs: code /mnt/c/Code/workspace/myapp-new-ui
```

**Special usage:**
```bash
gwt code
# Opens VS Code in the workspace directory itself
```

#### Create and open in Claude Code
```bash
gwt claude [branch]         # Tagless
gwt claude -b [branch]      # Tagged
```
Creates a worktree and immediately opens it in Claude Code.

**Example:**
```bash
gwt claude feature/refactor-api
# Creates worktree and runs: claude /mnt/c/Code/workspace/myapp

gwt claude -b feature/refactor-api
# Creates worktree and runs: claude /mnt/c/Code/workspace/myapp-refactor-api
```

#### Clear all worktrees
```bash
gwt clear
```
Removes all worktrees from the workspace directory.

**Example:**
```bash
gwt clear
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

Worktrees can be named in two ways:

### Tagless (default)
```
{project}
```
Uses just the repository name as the folder name.

**Example:**
- Repo: `myapp` → Worktree: `myapp`

### Tagged (with -b flag)
```
{project}-{tag}
```
Uses repository name plus branch tag.

**Examples:**
- Repo: `myapp`, Branch: `feature/new-ui` → Worktree: `myapp-new-ui`
- Repo: `company-myapp`, Branch: `hotfix/bug-123` → Worktree: `myapp-bug-123`

**Note:** If a tagless folder already exists, the tagged format is used automatically.

Where:
- `project` is the repository name (shortened if it contains hyphens)
- `tag` is the last component of the branch name

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
repos cache

# Fetch all repos daily
repos fetch

# Check repo status
repos status

# Switch all repos to main
repos main

# Clean up merged branches
repos clear   # Delete them

# Clean up old worktrees
gwt ls        # Review what's there
gwt clear     # Remove all if needed
```

## Usage Tips

1. **Repository Cache**: Run `repos cache` after adding new repositories
2. **Daily Updates**: Add `repos fetch` to your startup script for automatic updates
3. **Repository Management**: Use `repos status` to check all repos, `repos main` to switch to main branches
4. **Branch Cleanup**: Use `repos clear` to delete merged branches
5. **Worktree Cleanup**: Periodically run `gwt ls` to review and `gwt clear` to clean up
6. **Naming Strategy**: Use tagless worktrees for main work, tagged (-b) for multiple branches
7. **Branch Search**: When using `gwt add [repo] [branch]`, only one matching repo should exist
8. **Quick Access**: Use `gwt code` or `gwt claude` for immediate editor integration
