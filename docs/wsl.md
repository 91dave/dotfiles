# WSL Helpers

Utilities for managing Windows Subsystem for Linux (WSL) integration and binary resolution.

## Functions

### wsl_help

Displays help information for all WSL helper commands.

```bash
wsl_help
```

### wsl_get_bin

Finds the first available binary from a list of candidates, preferring Windows executables (.exe) over native Linux binaries.

```bash
wsl_get_bin [binary_names...]
```

**Parameters:**
- `binary_names...` - One or more binary names to search for

**Search order:**
1. Checks for `{binary}.exe` (Windows version)
2. Checks for `{binary}` (Linux version)
3. Returns the first match found

**Returns:**
The full name of the first available binary (`binary.exe` or `binary`)

**Examples:**
```bash
# Find docker or podman (prefers .exe versions)
DOCKER_BIN=$(wsl_get_bin docker podman)
echo $DOCKER_BIN
# Output: podman.exe (if docker.exe not found)

# Use the found binary
$DOCKER_BIN ps

# Find python
PYTHON=$(wsl_get_bin python3 python)
$PYTHON --version
```

**Use cases:**
1. **Cross-platform scripts**: Write scripts that work whether tools are installed in Windows or Linux
2. **Fallback binaries**: Specify multiple alternatives (e.g., `docker` or `podman`)
3. **Windows preference**: Automatically prefer Windows tools for better integration

**Example in a script:**
```bash
#!/bin/bash

# Find the best available container tool
CONTAINER_BIN=$(wsl_get_bin docker podman)

if [ -z "$CONTAINER_BIN" ]; then
    echo "Error: No container runtime found"
    exit 1
fi

echo "Using container runtime: $CONTAINER_BIN"
$CONTAINER_BIN run hello-world
```

### wsl_fix_exe

Enables WSL interoperability for executing Windows .exe files.

```bash
wsl_fix_exe
```

**What it does:**
- Checks if WSL interop is already enabled
- If not, registers the WSLInterop handler to execute Windows binaries
- Requires sudo permissions

**Example:**
```bash
wsl_fix_exe
# Output: ✅ WSL interop already enabled
# OR
# Output: 🔧 Enabling WSL interop...
#         ✅ WSL interop enabled
```

**When to use:**
- After a fresh WSL installation
- If you get "cannot execute binary file: Exec format error" when running .exe files
- If Windows commands suddenly stop working from WSL

**Technical details:**
- Registers the MZ (PE executable) magic number handler
- Points to `/init` as the interpreter for Windows binaries
- Uses `binfmt_misc` kernel feature

## Integration Examples

### Building Cross-Platform Scripts

```bash
#!/bin/bash

# Prefer Windows tools for better integration
GIT=$(wsl_get_bin git)
NODE=$(wsl_get_bin node)
NPM=$(wsl_get_bin npm)

# Use them transparently
$GIT status
$NODE --version
$NPM install
```

### Container Runtime Detection

```bash
# Used in dev.sh
DOCKER_BIN=$(wsl_get_bin docker podman)

if [ -n "$DOCKER_BIN" ]; then
    echo "Container runtime: $DOCKER_BIN"
    $DOCKER_BIN build -t myapp .
fi
```

### Tool Version Management

```bash
# Check both Windows and Linux installations
PYTHON_BIN=$(wsl_get_bin python python3)

if [ -n "$PYTHON_BIN" ]; then
    echo "Python found: $PYTHON_BIN"
    $PYTHON_BIN --version
else
    echo "Python not found. Please install python or python3"
fi
```

### Conditional Windows Integration

```bash
# Use Windows git if available for better credential management
GIT_BIN=$(wsl_get_bin git)

if [[ "$GIT_BIN" == *".exe" ]]; then
    echo "Using Windows Git (with credential manager)"
else
    echo "Using Linux Git"
fi

$GIT_BIN clone https://github.com/user/repo.git
```

## Troubleshooting

### .exe Files Not Working

```bash
# Try running a Windows command
cmd.exe /c "echo Hello"

# If it fails with "Exec format error", fix it:
wsl_fix_exe

# Try again
cmd.exe /c "echo Hello"
```

### Binary Not Found

```bash
# Check what's available
which docker.exe
which docker
which podman.exe
which podman

# Use wsl_get_bin to find the first available
DOCKER=$(wsl_get_bin docker podman)
echo $DOCKER
```

### Path Issues

```bash
# Windows executables should be in your PATH
echo $PATH | grep -o '/mnt/c/[^:]*' | grep -i windows

# Common Windows paths in WSL:
# /mnt/c/Windows/System32
# /mnt/c/Program Files/
# /mnt/c/Program Files (x86)/
```

## Integration with Other Libraries

### dev.sh Integration

The development helpers use Windows executables for better integration:

```bash
alias docker="podman.exe"
alias dotnet="dotnet.exe"
alias gh="gh.exe"
```

### git.sh Integration

Git operations use `git.exe` throughout for Windows credential manager integration:

```bash
git.exe status
git.exe worktree list
```

## Usage Tips

1. **Prefer Windows Tools**: Windows-installed tools often have better integration (e.g., Git credential manager, Docker Desktop)
2. **Binary Resolution**: Use `wsl_get_bin` when writing portable scripts
3. **Interop Issues**: Run `wsl_fix_exe` after WSL updates if .exe files stop working
4. **Performance**: Windows executables may have slight overhead; use Linux versions for performance-critical operations
5. **Path Conversion**: Remember to use `wslpath` when converting between Windows and WSL paths

## Why Prefer .exe Binaries?

1. **Credential Management**: Windows Git includes credential manager
2. **Docker Desktop**: Docker.exe integrates with Docker Desktop
3. **Consistency**: Same tool versions across Windows and WSL
4. **IDE Integration**: Better integration with Windows IDEs (VS Code, Visual Studio)
5. **File Watching**: Windows binaries handle file watching across WSL boundary

## Environment Considerations

### WSL 1 vs WSL 2

- **WSL 1**: Native interop, .exe files work by default
- **WSL 2**: Requires binfmt_misc registration (handled by `wsl_fix_exe`)

### Network Access

Windows executables in WSL use Windows networking stack:
- May have different firewall rules
- Different localhost behavior (use `host.docker.internal` for Docker Desktop)

### File System Performance

- Windows executables accessing `/mnt/c/` files: Fast
- Windows executables accessing WSL files (`\\wsl$\`): Slower
- Linux executables in WSL filesystem: Fastest
