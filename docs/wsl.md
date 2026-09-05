# WSL Helpers

Utilities for managing Windows Subsystem for Linux (WSL) integration and binary resolution.

## Environment Variables

Loaded automatically on shell startup:

| Variable | Description | Example |
|----------|-------------|---------|
| `USERPROFILE_WIN` | Windows user profile path (forward slashes) | `C:/Users/dave` |
| `USERPROFILE_WSL` | WSL-mapped user profile path | `/mnt/c/Users/dave` |

These are useful when passing paths to Windows executables (which can't resolve WSL paths):

```bash
# ✗ Won't work — .exe can't resolve WSL paths
pwsh.exe -File "$HOME/.pi/agent/script.ps1"

# ✓ Use the Windows-style path
pwsh.exe -File "$USERPROFILE_WIN/.pi/agent/script.ps1"
```

## Functions

### wecho

Runs `cmd.exe /c echo` with Windows variable substitution and strips carriage returns.

```bash
wecho %USERPROFILE%
# Output: C:\Users\dave

wecho %APPDATA%
# Output: C:\Users\dave\AppData\Roaming
```

Useful for resolving Windows environment variables that aren't available in WSL.

### wsl_help

Displays help information for all WSL helper commands.

```bash
wsl_help
```

### wsl_get_bin

**Note:** This function is deprecated. Use `wslexe get` instead.

Finds the first available binary from a list of candidates, preferring Windows executables (.exe) over native Linux binaries.

```bash
wsl_get_bin [binary_names...]
# Deprecated: use 'wslexe get [binary_names...]' instead
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

### wslexe

Manages WSL interoperability for executing Windows .exe files.

```bash
wslexe <subcommand>
```

**Subcommands:**

#### wslexe get

Finds the first available binary from a list of candidates, preferring Windows executables (.exe) over native Linux binaries.

```bash
wslexe get [binary_names...]
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
DOCKER_BIN=$(wslexe get docker podman)
echo $DOCKER_BIN
# Output: podman.exe (if docker.exe not found)

# Use the found binary
$DOCKER_BIN ps

# Find python
PYTHON=$(wslexe get python3 python)
$PYTHON --version
```

**Use cases:**
1. **Cross-platform scripts**: Write scripts that work whether tools are installed in Windows or Linux
2. **Fallback binaries**: Specify multiple alternatives (e.g., `docker` or `podman`)
3. **Windows preference**: Automatically prefer Windows tools for better integration

#### wslexe check

Checks if WSL interop is currently enabled.

```bash
wslexe check [-v]
```

**Options:**
- `-v` - Verbose mode (only shows message if enabled)

**Returns:**
- Exit code 0 if enabled
- Exit code 1 if disabled (with message to run `wslexe fix`)

**Example:**
```bash
wslexe check
# Output (if disabled): ❌ WSL interop not enabled. Run 'wslexe fix' to enable.

wslexe check -v
# Output (if enabled): ✅ WSL interop enabled
```

#### wslexe fix

Enables WSL interoperability for executing Windows .exe files.

```bash
wslexe fix
```

**What it does:**
- Registers the WSLInterop handler to execute Windows binaries
- Requires sudo permissions

**Example:**
```bash
wslexe fix
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

#### wslexe help

Displays usage information.

```bash
wslexe help
# or
wslexe -h
wslexe --help
```

**Note:** The shell automatically runs `wslexe check` on startup to validate WSL interop.

### wsltop

Resource overview for the WSL virtual machine: RAM and CPU broken down by distribution, podman
split out from the rest, container runtime state, and the running VM compared against what
`.wslconfig` permits.

```bash
wsltop            # full report
wsltop -s         # two lines: runtimes plus RAM and CPU
wsltop -c         # one line, used on interactive shell startup
wsltop -q         # this distro only, skips the Windows and interop calls
```

```
📦 Ubuntu-24.04 🟢 1 running    📦 podman-machine-default 🔴 stopped
📊 1.6 GB / 21.5 GB (10%)  █░░░░░░░░░  ·  load 1.49 over 12 vCPU
```

Runtime markers are 🟢 for containers running, 🟡 for a runtime present but idle, and 🔴 for a
stopped distribution.

**Why it works the way it does.** All WSL2 distributions share one utility virtual machine, so
`/proc/meminfo` is identical in every distribution and cgroups are shared across all of them.
Per-distribution memory therefore has to be attributed from `/proc`, whose PID namespaces are
genuinely isolated, and gathered by fanning out over `wsl.exe -d <distro>`. Container counts
come from that same scan rather than `podman ps`, which costs around 0.75 seconds because it
initialises the container store.

The distribution list is cached for 60 seconds in `$XDG_RUNTIME_DIR/wsltop-distros.cache`, so
`-s` and `-c` cost around 25 milliseconds. Override with `WSLTOP_CACHE_SECONDS`.

When the running VM does not match `.wslconfig`, the full report warns that a `wsl --shutdown`
is needed for the settings to take effect.

## Integration Examples

### Building Cross-Platform Scripts

```bash
#!/bin/bash

# Prefer Windows tools for better integration
GIT=$(wslexe get git)
NODE=$(wslexe get node)
NPM=$(wslexe get npm)

# Use them transparently
$GIT status
$NODE --version
$NPM install
```

### Container Runtime Detection

```bash
# Used in dev.sh
DOCKER_BIN=$(wslexe get docker podman)

if [ -n "$DOCKER_BIN" ]; then
    echo "Container runtime: $DOCKER_BIN"
    $DOCKER_BIN build -t myapp .
fi
```

### Tool Version Management

```bash
# Check both Windows and Linux installations
PYTHON_BIN=$(wslexe get python python3)

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
GIT_BIN=$(wslexe get git)

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
wslexe fix

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

# Use wslexe get to find the first available
DOCKER=$(wslexe get docker podman)
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
```

### git.sh Integration

Git operations use WSL-native `git` (and `gh`) throughout, not the Windows `.exe` builds:

```bash
git status
git worktree list
```

Native `git` does not use the Windows credential manager automatically. Configure a WSL credential helper (or use SSH remotes) so `repos fetch`/`main`/`clear` and `gwt` can authenticate. GUI launchers (`code`, `github`, `claude`) still go through `cmd.exe`.

## Usage Tips

1. **Prefer Windows Tools**: Windows-installed tools often have better integration (e.g., Git credential manager, Docker Desktop)
2. **Binary Resolution**: Use `wslexe get` when writing portable scripts (replaces deprecated `wsl_get_bin`)
3. **Interop Issues**: Run `wslexe fix` after WSL updates if .exe files stop working
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
