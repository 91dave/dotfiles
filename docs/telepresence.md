# Telepresence Helpers

Helper functions for working with [Telepresence](https://telepresence.io/), allowing you to intercept Kubernetes services and route traffic to your local development environment.

## Aliases

- `tps` - Check Telepresence connection status
  ```bash
  tps
  # Equivalent to: telepresence.exe status
  ```

- `tpl` - List active intercepts
  ```bash
  tpl
  # Equivalent to: telepresence.exe list
  ```

## Functions

### tphelp

Displays help information for all Telepresence commands.

```bash
tphelp
```

### tpc

Connects to a Kubernetes namespace via Telepresence.

```bash
tpc [namespace]
```

**Parameters:**
- `namespace` - The Kubernetes namespace to connect to

**Example:**
```bash
tpc myapp
# Output: 🔗 Connecting to namespace myapp...
```

**What it does:**
- Establishes Telepresence connection to the specified namespace
- Configures the Traffic Manager in the same namespace

### tpi

Starts a traffic intercept for a service.

```bash
tpi [component] [port]
tpi [namespace] [component] [port]
```

**Parameters:**
- `namespace` - (Optional) Kubernetes namespace (will auto-connect if provided)
- `component` - Name of the Kubernetes service to intercept
- `port` - Local port to route traffic to

**Examples:**
```bash
# Intercept within already-connected namespace
tpi myapp-api 8080

# Connect to namespace and intercept
tpi myapp myapp-api 8080
```

**What it does:**
1. Connects to namespace if provided
2. Creates an intercept for the specified service
3. Routes HTTP traffic on the specified port to your local machine
4. Saves the component name to `~/.tpi.tmp` for cleanup
5. Mounts are disabled for performance

**Use case:**
Run your service locally on port 8080, and all Kubernetes traffic to that service gets routed to your local instance.

### tpii

Interactive intercept that automatically disconnects when you press Enter.

```bash
tpii [component] [port]
tpii [namespace] [component] [port]
```

**Parameters:**
Same as `tpi`

**Example:**
```bash
tpii myapp api 8080

# Output:
# 🔗 Connecting to namespace myapp...
# 🎯 Intercepting api on port 8080...
# ✅ Intercept active
#
# 🎯 Telepresence active — press Enter to disconnect
```

**What it does:**
1. Calls `tpi` to start the intercept
2. Waits for you to press Enter
3. Automatically calls `tpq` to clean up

**Use case:**
Quick testing sessions where you want to automatically clean up when done.

### tpq

Quits Telepresence and closes any active intercepts.

```bash
tpq
```

**Example:**
```bash
tpq
# Output:
# 🔌 Closing intercept on myapp-api...
# 👋 Disconnecting from telepresence...
```

**What it does:**
1. Reads the component name from `~/.tpi.tmp`
2. Leaves the active intercept
3. Cleans up the temporary file
4. Quits Telepresence entirely

## Workflow Examples

### Local Development with Remote Dependencies

```bash
# 1. Connect to your dev namespace
tpc dev

# 2. Start your local service
cd myapp-api
dotnet run --urls http://localhost:8080

# 3. In another terminal, start the intercept
tpi myapp-api 8080

# 4. Test from another service in the cluster
# Traffic to myapp-api in Kubernetes now goes to localhost:8080

# 5. When done, disconnect
tpq
```

### Quick Testing Session

```bash
# Start your service locally
cd myapp-api
npm start  # Runs on port 3000

# In another terminal, use interactive intercept
tpii dev myapp-api 3000

# ... test your changes ...
# Press Enter when done (auto-cleanup)
```

### Debugging Microservice Interactions

```bash
# Connect and intercept
tpc staging
tpi user-service 8080

# In your IDE, set breakpoints and run locally
# Traffic from other services will hit your breakpoints

# Check intercept status
tps
tpl

# Disconnect when done
tpq
```

### Multiple Service Development

```bash
# Terminal 1: API service
cd myapp-api
dotnet run --urls http://localhost:8080
tpi myapp myapp-api 8080

# Terminal 2: Worker service
cd myapp-worker
dotnet run
tpi myapp myapp-worker 8081

# Both services now intercept traffic from Kubernetes
# They can still communicate with each other via Kubernetes service names

# When done
tpq  # Run in each terminal
```

## Configuration Notes

### HTTP vs TCP Intercepts

The helpers use `--port $port:http` which configures HTTP intercepts. This is suitable for most web services.

For TCP-only services, you would need to modify the command to use `--port $port`.

### Mounts

Mounts are disabled (`--mount false`) for better performance. If you need access to Kubernetes volumes, you'll need to enable mounts manually:

```bash
telepresence.exe intercept myapp-api --port 8080:http --mount /mnt/telepresence
```

### Traffic Manager

The helpers place the Traffic Manager in the same namespace as your workloads (`--manager-namespace $namespace`). This is the recommended approach for namespace isolation.

## Troubleshooting

### Check Connection Status
```bash
tps
```

### View Active Intercepts
```bash
tpl
```

### Reset Everything
```bash
# Quit and reconnect
tpq
tpc myapp
```

### Cannot Connect
- Ensure you have kubectl access to the cluster
- Verify the namespace exists: `kubectl get ns`
- Check Traffic Manager is deployed: `kubectl get deploy -n myapp`

### Intercept Not Working
- Verify service exists: `kubectl get svc -n myapp`
- Check local service is running on the specified port
- Ensure no firewall is blocking the port
- Try running `tpl` to see if intercept is active

## Usage Tips

1. **Development Workflow**: Use `tpii` for quick iterations, `tpi` for longer sessions
2. **Always Disconnect**: Run `tpq` when done to free cluster resources
3. **Port Conflicts**: Ensure your local service runs on the port you specify in the intercept
4. **Multiple Intercepts**: You can intercept multiple services, but track them carefully
5. **Testing**: After connecting, test with `curl` from another pod to verify routing
