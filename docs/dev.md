# Development Helpers

General development utilities and aliases for working with common tools in a Windows/WSL2 environment.

## Aliases

These aliases provide seamless access to Windows-installed development tools from within WSL2:

```bash
alias docker="podman.exe"
alias docker-compose="podman.exe compose"
alias dotnet="dotnet.exe"
alias gh="gh.exe"
```

## Functions

### dev_help

Displays help information for all development helper commands.

```bash
dev_help
```

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
1. Retrieves your Windows NuGet.Config file
2. Copies it to the current directory
3. Builds the Docker image (tagged as `temp`)
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

## Usage Tips

1. **Podman vs Docker**: These scripts use `podman.exe` as it's the preferred container runtime. Docker commands work transparently.
2. **NuGet Authentication**: Use `push_docker` when building containers that need access to private NuGet feeds.
3. **Path Conversions**: Windows paths are automatically converted using `wslpath` where needed.
4. **Tool Versions**: All aliased tools use the Windows versions, ensuring consistency across environments.
