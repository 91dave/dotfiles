# AWS Helpers

Helper functions and utilities for working with Amazon Web Services (AWS) in a WSL2 environment.

## Configuration

```bash
export AWS_CONFIG_WSL=true
```

When set to `true`, AWS credential operations will update both WSL and Windows credentials automatically.

## Functions

### aws_help

Displays help information for all AWS helper commands.

```bash
aws_help
```

### aws_key_rotate

Automatically rotates your AWS access keys with zero downtime.

```bash
aws_key_rotate
```

**How it works:**
1. Validates you have fewer than 2 access keys
2. Creates a new access key
3. Updates credentials in both WSL and Windows (if `AWS_CONFIG_WSL=true`)
4. Waits 5 seconds for propagation
5. Tests the new credentials
6. Disables and deletes the old access key

**Example output:**
```
🔑 Rotating AWS access keys for myusername
➕ Creating new access key...
🔄 Updating credentials...
🗑️  Disabling old key AKIA...
🧪 Testing credentials...
✅ Key rotation complete
```

### aws_secrets_json_validity

Validates JSON format of AWS Secrets Manager secrets matching a pattern.

```bash
aws_secrets_json_validity [pattern]
```

**Parameters:**
- `pattern` - String pattern to filter secrets (supports regex)

**Example:**
```bash
# Check all secrets containing "prod"
aws_secrets_json_validity prod

# Check secrets in a specific path
aws_secrets_json_validity myapp/
```

**Output:**
```
🔍 Checking JSON validity for secrets matching 'prod'...
  ✅ prod/database-config
  ❌ prod/api-keys (invalid JSON)
  ⏭️  prod/api-token (plaintext, skipped)
```

### aws_role_assume

Assumes an IAM role and exports credentials for both WSL and Windows environments.

```bash
aws_role_assume [arn]
```

**Parameters:**
- `arn` - ARN of the role to assume (optional - clears credentials if not provided)

**Example:**
```bash
# Assume a role
aws_role_assume arn:aws:iam::123456789012:role/MyRole

# Clear assumed role credentials
aws_role_assume
```

**Output:**
```
🔐 Assuming role...
✅ Now logged in as arn:aws:sts::123456789012:assumed-role/MyRole/session

📋 Windows credentials (copy to CMD):
   set AWS_ACCESS_KEY_ID=ASIA...
   set AWS_SECRET_ACCESS_KEY=...
   set AWS_SESSION_TOKEN=...
```

### aws_role_clear

Clears assumed role credentials from the current WSL session.

```bash
aws_role_clear
```

**Output:**
```
🔓 AWS credentials cleared from WSL

📋 To clear from Windows:
   set AWS_ACCESS_KEY_ID=
   set AWS_SECRET_ACCESS_KEY=
   set AWS_SESSION_TOKEN=
```

### aws_ecr

Logs into AWS Elastic Container Registry (ECR) in a specified region.

```bash
aws_ecr [region]
```

**Parameters:**
- `region` - AWS region (e.g., `us-east-1`, `eu-west-1`)

**Example:**
```bash
aws_ecr us-east-1
```

**Output:**
```
🐳 Logging into ECR (us-east-1)...
✅ Logged in to 123456789012.dkr.ecr.us-east-1.amazonaws.com
```

## Usage Tips

1. **Key Rotation**: Run `aws_key_rotate` regularly to maintain security best practices
2. **Role Switching**: Use `aws_role_assume` for cross-account access or elevated permissions
3. **Multi-Environment**: Set `AWS_CONFIG_WSL=true` to keep WSL and Windows credentials in sync
4. **ECR Access**: Remember to log into ECR in each region you need to push/pull images
