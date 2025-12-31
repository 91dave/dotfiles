# Terraform Helpers

Opinionated helpers for working with [Terraform](https://developer.hashicorp.com/terraform) infrastructure as code in a Windows/WSL2 environment.

## Aliases

- `tf` - Short alias for terraform
  ```bash
  tf plan
  # Equivalent to: terraform.exe plan
  ```

- `terraform` - Main terraform command
  ```bash
  terraform apply
  # Equivalent to: terraform.exe apply
  ```

- `tfinit` - Initialize terraform
  ```bash
  tfinit
  # Equivalent to: terraform.exe init
  ```

## Functions

### tfhelp

Displays help information for all Terraform helper commands.

```bash
tfhelp
```

### tffmt

Recursively formats all Terraform files in the current directory and subdirectories.

```bash
tffmt
```

**Example:**
```bash
cd /path/to/terraform/project
tffmt
# Output: (lists all formatted files)
```

**Use cases:**
- Before committing changes
- Enforcing consistent code style
- Part of CI/CD pipeline

### tfvalid

Validates the Terraform configuration in the current directory.

```bash
tfvalid
```

**Example:**
```bash
tfvalid
# Output: Success! The configuration is valid.
```

**What it checks:**
- Syntax errors
- Invalid resource references
- Type mismatches
- Required argument validation

### tfplan

Generates a Terraform plan file with support for different variable files.

```bash
tfplan [vars-file] [plan-name]
tfplan [plan-name]
```

**Parameters:**
- `vars-file` - (Optional) Name of the tfvars file in `envs/` directory (without extension)
- `plan-name` - Name for the plan file (without extension)

**Defaults:**
- If only one argument: uses `playground.tfvars` as vars-file
- Plan files saved to: `./plans/[plan-name].tfplan`
- Vars files loaded from: `./envs/[vars-file].tfvars`

**Examples:**
```bash
# Use playground vars, create "test" plan
tfplan test
# Creates: plans/test.tfplan
# Uses: envs/playground.tfvars

# Use dev vars, create "deploy" plan
tfplan dev deploy
# Creates: plans/deploy.tfplan
# Uses: envs/dev.tfvars
```

**Expected directory structure:**
```
terraform-project/
├── envs/
│   ├── playground.tfvars
│   ├── dev.tfvars
│   ├── staging.tfvars
│   └── prod.tfvars
├── plans/
│   └── (generated .tfplan files)
├── main.tf
└── variables.tf
```

### tfdestroy

Generates a destruction plan (plan with `-destroy` flag).

```bash
tfdestroy [vars-file] [plan-name]
tfdestroy [plan-name]
```

**Parameters:**
Same as `tfplan`

**Examples:**
```bash
# Create destruction plan with playground vars
tfdestroy cleanup

# Create destruction plan with staging vars
tfdestroy staging teardown
```

**Safety:**
- Always review the plan before applying: `tf show plans/cleanup.tfplan`
- Destruction plans clearly show what will be deleted

### tftest

Sets up a local test environment for Terraform development.

```bash
tftest
```

**What it creates:**
1. `envs/playground.tfvars` - Empty tfvars file for local testing
2. `backend_override.tf` - Configures local backend instead of remote

**Example:**
```bash
cd new-terraform-project
tftest
# Output:
# 🧪 Setting up local test environment...
# ✅ Created envs/playground.tfvars
# ✅ Created backend_override.tf
```

**Use cases:**
- Testing infrastructure changes locally
- Developing new modules
- Experimenting without affecting remote state

**Note:** Add `backend_override.tf` to `.gitignore` to prevent committing local backend config.

## Workflow Examples

### Setting Up a New Project

```bash
# Clone the repo
cd terraform-project

# Initialize
tfinit

# Set up local testing
tftest

# Format code
tffmt

# Validate
tfvalid

# Create a test plan
tfplan test

# Review the plan
tf show plans/test.tfplan
```

### Development Workflow

```bash
# Make changes to .tf files
vim main.tf

# Format
tffmt

# Validate
tfvalid

# Create plan
tfplan dev review-changes

# Review plan
tf show plans/review-changes.tfplan

# Apply if looks good
tf apply plans/review-changes.tfplan
```

### Multi-Environment Deployment

```bash
# Development
tfplan dev dev-deploy
tf apply plans/dev-deploy.tfplan

# Staging (after testing in dev)
tfplan staging staging-deploy
tf apply plans/staging-deploy.tfplan

# Production (after testing in staging)
tfplan prod prod-deploy
# Review carefully!
tf show plans/prod-deploy.tfplan
tf apply plans/prod-deploy.tfplan
```

### Safe Cleanup

```bash
# Generate destruction plan
tfdestroy staging cleanup-old-resources

# Review what will be destroyed
tf show plans/cleanup-old-resources.tfplan

# Apply destruction (if sure)
tf apply plans/cleanup-old-resources.tfplan
```

### Pre-Commit Checks

```bash
# Run before every commit
tffmt && tfvalid && tfplan pre-commit

# Review changes
tf show plans/pre-commit.tfplan
```

## Directory Structure

Recommended structure for working with these helpers:

```
terraform-project/
├── envs/
│   ├── playground.tfvars      # Local testing (not committed)
│   ├── dev.tfvars             # Development environment
│   ├── staging.tfvars         # Staging environment
│   └── prod.tfvars            # Production environment
├── plans/
│   └── *.tfplan               # Generated plans (not committed)
├── modules/
│   ├── networking/
│   ├── compute/
│   └── storage/
├── main.tf
├── variables.tf
├── outputs.tf
├── backend.tf
├── backend_override.tf        # Local backend (not committed)
└── .gitignore
```

**.gitignore recommendations:**
```gitignore
# Terraform
*.tfstate
*.tfstate.*
.terraform/
.terraform.lock.hcl

# Local testing
backend_override.tf
envs/playground.tfvars

# Generated plans
plans/
```

## Variable Files

### Creating Variable Files

Each environment should have its own `.tfvars` file:

**envs/dev.tfvars:**
```hcl
environment     = "dev"
instance_type   = "t3.small"
instance_count  = 2
enable_monitoring = false
```

**envs/prod.tfvars:**
```hcl
environment     = "prod"
instance_type   = "t3.large"
instance_count  = 5
enable_monitoring = true
```

### Using Variable Files

```bash
# Always specify the environment explicitly for non-playground
tfplan dev my-changes
tfplan staging my-changes
tfplan prod my-changes

# Playground is the default for quick testing
tfplan quick-test
```

## Best Practices

1. **Always Format**: Run `tffmt` before committing
2. **Always Validate**: Run `tfvalid` before creating plans
3. **Use Plans**: Never run `terraform apply` without a plan file
4. **Environment Separation**: Use separate variable files for each environment
5. **Review Plans**: Always review with `tf show plans/[name].tfplan` before applying
6. **Plan Naming**: Use descriptive names that indicate the change (e.g., `add-monitoring`, `scale-up`)
7. **Local Testing**: Use `tftest` to set up local testing without affecting remote state
8. **Version Control**: Don't commit plan files, playground.tfvars, or backend_override.tf

## Troubleshooting

### Validate Fails
```bash
# Check syntax
tffmt
tfvalid

# Check for missing variables
tf validate
```

### Plan Creation Fails
```bash
# Ensure initialized
tfinit

# Check variable file exists
ls envs/*.tfvars

# Verify workspace
tf workspace show
```

### State Lock Issues
```bash
# Check who has the lock
tf force-unlock [LOCK_ID]

# Only use if you're certain no one else is running terraform
```

## Usage Tips

1. **Plan Files**: Store plans temporarily, don't commit them to version control
2. **Environment Vars**: Keep sensitive values in environment variables, not in .tfvars files
3. **Local Backend**: Use `tftest` for local experimentation without state conflicts
4. **Review Carefully**: Always use `tf show` to review plans, especially for production
5. **Naming Convention**: Use consistent naming for plans (e.g., `{env}-{date}-{description}`)
