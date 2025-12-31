# Dotfiles Library Documentation

Comprehensive documentation for all helper functions and aliases in `/dotfiles/lib`.

## Quick Reference

All libraries include a help function to display available commands:

- `aws_help` - AWS helpers
- `dev_help` - Development helpers
- `khelp` - Kubernetes helpers
- `tphelp` - Telepresence helpers
- `tfhelp` - Terraform helpers
- `wsl_help` - WSL integration helpers

## Libraries

### AWS Helpers
**File:** `dotfiles/lib/aws.sh`

Helper functions for working with Amazon Web Services in a WSL2 environment.

**Key Features:**
- Automatic AWS access key rotation
- Role assumption with cross-environment credential management
- JSON validation for Secrets Manager
- ECR authentication

**[Full Documentation →](aws.md)**

---

### Development Helpers
**File:** `dotfiles/lib/dev.sh`

General development utilities and tool aliases for Windows/WSL2 integration.

**Key Features:**
- Seamless Windows tool integration (Docker/Podman, .NET, GitHub CLI)
- Unix timestamp conversion
- Docker builds with NuGet configuration

**[Full Documentation →](dev.md)**

---

### Git & Worktree Management
**File:** `dotfiles/lib/git.sh`

Opinionated helpers for managing multiple git repositories and worktrees.

**Key Features:**
- Repository discovery and caching
- Automatic fetch and pull for all repos
- Advanced git worktree management
- IDE integration (VS Code, Claude Code)

**[Full Documentation →](git.md)**

---

### Kubernetes Helpers
**File:** `dotfiles/lib/kubernetes.sh`

Comprehensive helpers and shortcuts for working with Kubernetes clusters.

**Key Features:**
- Quick context switching between clusters
- Extensive pod, service, and node management aliases
- Multi-pod operations (execute, copy files)
- Cluster auditing and health checks
- Helm release management

**[Full Documentation →](kubernetes.md)**

---

### Telepresence Helpers
**File:** `dotfiles/lib/telepresence.sh`

Helpers for intercepting Kubernetes services and routing traffic to local development.

**Key Features:**
- Simple namespace connection
- Traffic interception with auto-cleanup
- Interactive debugging sessions
- Multiple intercept management

**[Full Documentation →](telepresence.md)**

---

### Terraform Helpers
**File:** `dotfiles/lib/terraform.sh`

Opinionated helpers for Terraform infrastructure as code workflows.

**Key Features:**
- Multi-environment support with variable files
- Plan generation and management
- Local testing environment setup
- Destruction plan safety

**[Full Documentation →](terraform.md)**

---

### WSL Integration Helpers
**File:** `dotfiles/lib/wsl.sh`

Utilities for managing WSL integration and binary resolution.

**Key Features:**
- Smart binary detection (Windows vs Linux)
- WSL interop troubleshooting
- Cross-platform script support

**[Full Documentation →](wsl.md)**

---

### Quartex Helpers
**File:** `dotfiles/lib/quartex-secret.sh`

Project-specific shortcuts for Quartex infrastructure.

**Key Features:**
- Quick SSH access to TeamCity server

**[Full Documentation →](quartex.md)**

---

## Common Workflows

### Daily Development

```bash
# Update all repositories
fetch_repos

# Start Kubernetes work
use-dev
kgp myapp

# Local development with Telepresence
tpii myapp myapp-api 8080
```

### Infrastructure Changes

```bash
# Make Terraform changes
cd terraform-project
tffmt && tfvalid

# Plan for each environment
tfplan dev review
tfplan staging review
tfplan prod review

# Apply after review
tf apply plans/dev-review.tfplan
```

### Multi-branch Development

```bash
# Create worktrees for multiple features
gwt add feature/user-auth
gwt code feature/admin-panel

# Work in parallel
cd /mnt/c/Code/workspace/myapp-user-auth
# ... make changes ...
```

### AWS Operations

```bash
# Rotate keys
aws_key_rotate

# Assume role for deployment
aws_role_assume arn:aws:iam::123456789012:role/DeployRole

# Log into ECR
aws_ecr us-east-1

# Deploy
docker push ...

# Clear credentials
aws_role_clear
```

## Installation

These helpers are installed as part of the dotfiles setup. See the [main README](../README.md) for installation instructions.

## Contributing

When adding new helpers:

1. Add functions to the appropriate file in `dotfiles/lib/`
2. Include a `*_help` function that documents the new commands
3. Update the corresponding documentation file in `docs/`
4. Add examples and use cases

## Support

For issues or questions:
- Check the specific library documentation
- Run the `*_help` function for quick reference
- Review the source code in `dotfiles/lib/`
