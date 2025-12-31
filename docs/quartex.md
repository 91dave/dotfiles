# Quartex Helpers

Project-specific shortcuts for Quartex infrastructure.

## Aliases

### quartex

Quick SSH connection to the Quartex TeamCity server.

```bash
quartex
```

**Equivalent to:**
```bash
ssh -i ~/Quartex.pem ubuntu@teamcity.quartex.uk
```

**Requirements:**
- SSH key file must exist at `~/Quartex.pem`
- Key must have correct permissions (usually `chmod 600 ~/Quartex.pem`)
- Access to the teamcity.quartex.uk server

**Example:**
```bash
# Connect to Quartex TeamCity
quartex

# Once connected, you can:
# - Check TeamCity logs
# - Manage build agents
# - Troubleshoot build issues
# - Update server configuration
```

## Setup

### Initial Setup

1. Obtain the `Quartex.pem` SSH key
2. Copy it to your home directory:
   ```bash
   cp /path/to/Quartex.pem ~/Quartex.pem
   ```
3. Set correct permissions:
   ```bash
   chmod 600 ~/Quartex.pem
   ```
4. Test the connection:
   ```bash
   quartex
   ```

### Troubleshooting

#### Permission Denied (publickey)

```bash
# Check key file exists
ls -la ~/Quartex.pem

# Fix permissions if needed
chmod 600 ~/Quartex.pem

# Test SSH connection with verbose output
ssh -v -i ~/Quartex.pem ubuntu@teamcity.quartex.uk
```

#### Key File Not Found

```bash
# Verify path
echo ~/Quartex.pem

# If key is elsewhere, create a symlink
ln -s /actual/path/to/Quartex.pem ~/Quartex.pem
```

#### Connection Timeout

```bash
# Check network connectivity
ping teamcity.quartex.uk

# Check if you're on VPN (if required)
# Try with verbose output
ssh -v -i ~/Quartex.pem ubuntu@teamcity.quartex.uk
```

## Common Tasks

### Check TeamCity Status

```bash
quartex
sudo systemctl status teamcity
```

### View TeamCity Logs

```bash
quartex
sudo journalctl -u teamcity -f
```

### Restart TeamCity Service

```bash
quartex
sudo systemctl restart teamcity
```

### Check Disk Space

```bash
quartex
df -h
```

### Check Build Agent Status

```bash
quartex
# Navigate to agents directory
cd /opt/teamcity/buildAgent
./bin/agent.sh status
```

## Security Notes

1. **Key Protection**: Never commit `Quartex.pem` to version control
2. **Key Permissions**: Always maintain `600` permissions on the key file
3. **Access Control**: Only use the key for authorized purposes
4. **Key Rotation**: Update the key if it's been compromised

## Adding to .gitignore

Ensure your SSH keys are never committed:

```bash
echo "*.pem" >> ~/.gitignore_global
git config --global core.excludesfile ~/.gitignore_global
```

Or in your project `.gitignore`:
```
# SSH Keys
*.pem
*.key
```
