# Development Helpers

General development utilities and aliases for working with common tools in a Windows/WSL2 environment.

## Configuration

### WARN_MISSING_HELPERS

Controls whether warnings are shown when optional helper utilities are missing.

```bash
WARN_MISSING_HELPERS=true  # Default: show warnings
```

Set to `false` in your shell config to suppress warnings about missing tools like `batcat`, `eza`, or `fzf`.

## Aliases

These aliases provide seamless access to Windows-installed development tools from within WSL2:

```bash
alias docker="podman.exe"
alias docker-compose="podman.exe compose"
alias dotnet="dotnet.exe"
alias gh="gh.exe"
alias claude="npx @anthropic-ai/claude-code"
alias bat="batcat"  # Shorter alias for batcat
```

## Functions

### dev_help

Displays help information for all development helper commands.

```bash
dev_help
```

### ce

Container engine manager for checking and starting the container engine (Podman).

```bash
ce <command>
```

**Commands:**
- `check [-v]` - Check if container engine is running (-v for verbose output)
- `fix` - Start the container engine
- `help` - Show help message

**Examples:**
```bash
# Check if container engine is running (silent if OK)
ce check

# Check with verbose output
ce check -v

# Start the container engine if it's not running
ce fix
```

**Auto-check on startup:**
The container engine status is automatically checked when you start an interactive shell. If it's not running, you'll see a warning with instructions to fix it.

### pod

Interactive container manager with fzf integration.

```bash
pod [command]
```

**Commands:**
- `logs` - View container logs (default action in preview)
- `stop` - Stop the container
- `attach` - Attach to the container
- `rm` - Remove the container
- `sh` - Shell into the container

**Example:**
```bash
# Select a container and view logs
pod logs

# Select a container and shell into it
pod sh

# Select a container and stop it
pod stop
```

The fzf preview shows live container logs while you browse.

### epoch

Converts Unix timestamps to human-readable dates.

```bash
epoch [timestamp]
```

**Parameters:**
- `timestamp` - Unix epoch timestamp (seconds since 1970-01-01)

**Example:**
```bash
# Convert a timestamp
epoch 1703001600

# Output: Tue Dec 19 04:00:00 PM EST 2023
```

**Common use cases:**
```bash
# Get timestamp from a log file and convert it
cat app.log | grep "error" | awk '{print $1}' | xargs -I {} epoch {}

# Convert current time
epoch $(date +%s)
```

### get_nuget_config

Retrieves the path to the Windows NuGet.Config file in WSL format.

```bash
get_nuget_config
```

**Example:**
```bash
# Get the config path
config_path=$(get_nuget_config)
echo $config_path
# Output: /mnt/c/Users/YourName/AppData/Roaming/NuGet/NuGet.Config

# View the config
cat $(get_nuget_config)
```

**Use cases:**
- Accessing private NuGet feeds configured in Windows
- Copying NuGet configuration into Docker containers
- Debugging NuGet authentication issues

### push_docker

Builds a Docker image with your Windows NuGet configuration included.

```bash
push_docker
```

**How it works:**
1. Retrieves your Windows NuGet.Config file using `wslexe get`
2. Copies it to the current directory
3. Builds the Docker image (tagged as `temp`) using the available container engine
4. Removes the temporary NuGet.Config copy

**Example:**
```bash
# Build a .NET application image with NuGet auth
cd /path/to/dotnet/project
push_docker
```

**Dockerfile requirements:**
Your Dockerfile should copy and use the NuGet.Config:
```dockerfile
FROM mcr.microsoft.com/dotnet/sdk:8.0
WORKDIR /app
COPY NuGet.Config ./
COPY *.csproj ./
RUN dotnet restore
COPY . ./
RUN dotnet build
```

## Tool Access

### Docker (Podman)

Since `docker` is aliased to `podman.exe`, all Docker commands work seamlessly:

```bash
# Standard Docker commands
docker ps
docker images
docker run -d nginx
docker-compose up -d
```

### .NET

Access the Windows-installed .NET SDK:

```bash
# Check version
dotnet --version

# Create a new project
dotnet new webapi -n MyApi

# Run tests
dotnet test

# Build and run
dotnet run
```

### GitHub CLI

Use the Windows-installed GitHub CLI:

```bash
# View pull requests
gh pr list

# Create a PR
gh pr create

# Check workflow runs
gh run list
```

### Claude Code

Access Claude Code via npx:

```bash
# Start Claude Code in current directory
claude

# Start in specific directory
claude /path/to/project
```

## Optional Helper Utilities

The dev helpers integrate with several optional utilities to enhance your development experience. These tools are automatically detected on shell startup.

### batcat

A `cat` replacement with syntax highlighting and Git integration.

**Installation:**
```bash
sudo apt install bat
```

**Usage:**
```bash
# View a file with syntax highlighting
bat file.sh

# Shorter alias available
bat file.sh
```

### eza

A modern replacement for `ls` with tree view support.

**Installation:**
```bash
sudo apt install eza
```

**Usage:**
```bash
# List files with color and icons
eza

# Tree view
eza --tree

# Detailed list
eza -l
```

### fzf

A command-line fuzzy finder with enhanced preview support.

**Installation:**
```bash
git clone --depth 1 https://github.com/junegunn/fzf.git ~/.fzf
~/.fzf/install
```

**Usage:**
```bash
# Fuzzy find files with preview (Ctrl+T)
# Press Ctrl+T in your terminal to trigger file search

# Fuzzy find with preview using alias
pf

# Enhanced directory search (when using cd **)
cd **<TAB>
```

**Enhanced Previews:**
The fzf integration includes custom previews:
- **Files**: Shows syntax-highlighted content using `batcat`
- **Directories**: Shows tree structure using `eza`
- **CD command**: Shows directory tree when using tab completion

## Usage Tips

1. **Podman vs Docker**: These scripts use `podman.exe` as it's the preferred container runtime. Docker commands work transparently.
2. **NuGet Authentication**: Use `push_docker` when building containers that need access to private NuGet feeds.
3. **Path Conversions**: Windows paths are automatically converted using `wslpath` where needed.
4. **Tool Versions**: All aliased tools use the Windows versions, ensuring consistency across environments.
5. **Container Engine**: The `ce` command helps manage the container engine. If you see startup warnings, run `ce fix` to start it.
6. **Helper Utilities**: Install `batcat`, `eza`, and `fzf` for enhanced file browsing and search capabilities. Set `WARN_MISSING_HELPERS=false` if you don't want installation reminders.
