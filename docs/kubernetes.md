# Kubernetes Helpers

Comprehensive helpers and shortcuts for working with Kubernetes clusters. Run `khelp` to see all available commands.

## Configuration

```bash
# Kubernetes cluster nicknames
PREF_k8s_clusters="dev test prod"
PREF_k8s_audit_clusters="test dev"
PREF_k8s_audit_namespaces="testing qa uat dev stage"

# Map cluster nicknames to kubectl contexts
PREF_k8s_dev=development
PREF_k8s_test=testing
PREF_k8s_prod=production
```

## Context Switching

Dynamic aliases are created for each configured cluster:

```bash
use-dev      # Switch to development context
use-test     # Switch to testing context
use-prod     # Switch to production context
```

**Example:**
```bash
use-dev
kubectl get pods -n myapp
```

## Aliases

### Namespace Management
- `kgns` - List all namespaces
  ```bash
  kgns
  # Equivalent to: kubectl get namespaces
  ```

### Pod Management
- `kkp [ns] [pod]` - Delete (kill) a pod
  ```bash
  kkp myapp my-pod-123
  # Equivalent to: kubectl delete pod -n myapp my-pod-123
  ```

### Service Management
- `kgs [ns]` - List services in namespace
  ```bash
  kgs myapp
  # Equivalent to: kubectl get services -n myapp
  ```

### Pod Details
- `kdp [ns] [pod]` - Describe a pod
  ```bash
  kdp myapp my-pod-123
  # Equivalent to: kubectl describe pod -n myapp my-pod-123
  ```

- `kgl [ns] [pod]` - Get pod logs
  ```bash
  kgl myapp my-pod-123
  # Equivalent to: kubectl logs -n myapp my-pod-123
  ```

- `kgxx [ns] [pod]` - Execute interactive shell in pod
  ```bash
  kgxx myapp my-pod-123
  # Equivalent to: kubectl exec -tin myapp my-pod-123
  ```

### Node Management
- `kgn` - List nodes
  ```bash
  kgn
  # Equivalent to: kubectl get nodes
  ```

- `kdn [node]` - Describe a node
  ```bash
  kdn node-1
  # Equivalent to: kubectl describe node node-1
  ```

### Generic Resource Operations
- `kg [ns] [resource]` - Get any resource
  ```bash
  kg myapp deployments
  # Equivalent to: kubectl get -n myapp deployments
  ```

- `kd [ns] [resource]` - Describe any resource
  ```bash
  kd myapp deployment/myapp
  # Equivalent to: kubectl describe -n myapp deployment/myapp
  ```

### Helm
- `hls [ns]` - List Helm releases in namespace
  ```bash
  hls myapp
  # Equivalent to: helm list -an myapp
  ```

## Functions

### khelp

Displays comprehensive help for all Kubernetes commands.

```bash
khelp
```

### kgp

Lists pods in a namespace, optionally filtered by app name.

```bash
kgp [namespace] [app]
```

**Examples:**
```bash
# List all pods in namespace
kgp myapp

# List pods with "api" in the name
kgp myapp api
```

### kgr

Gets the rollout status for a deployment.

```bash
kgr [namespace] [deployment]
```

**Example:**
```bash
kgr myapp myapp-api
# Output: deployment "myapp-api" successfully rolled out
```

### kgxh

Executes a command in a pod (with header showing connection details).

```bash
kgxh [namespace] [app] [command...]
```

**How it works:**
- Finds the first running pod matching the app name
- Excludes terminating pods and pods with 0 containers ready
- Displays connection information before executing

**Example:**
```bash
kgxh myapp api /bin/bash
# Output:
# 🔗 Connecting to myapp-api-7d4f5b8c-9x2k1...
#    kubectl exec -tin myapp myapp-api-7d4f5b8c-9x2k1 -- /bin/bash
```

### kgx

Executes a command in a pod (silent, no header).

```bash
kgx [namespace] [app] [command...]
```

**Example:**
```bash
# Check disk space
kgx myapp api df -h

# Read a file
kgx myapp api cat /app/config.json
```

### kcp

Copies a file to all pods matching an app name.

```bash
kcp [namespace] [app] [source] [destination]
```

**Example:**
```bash
# Copy config to all API pods
kcp myapp api ./new-config.json /app/config.json
```

### kppn

Shows pod distribution across nodes.

```bash
kppn [namespace]
```

**Examples:**
```bash
# All pods across all namespaces
kppn
# Output:
# 📊 156 pods across 8 nodes (all namespaces)
#      12 node-1
#      18 node-2
#      19 node-3

# Pods in specific namespace
kppn myapp
# Output:
# 📊 24 pods across 4 nodes (myapp)
#       6 node-1
#       6 node-2
#       6 node-3
#       6 node-4
```

### kgo

Lists pods that are not ready or terminating.

```bash
kgo [namespace]
```

**Example:**
```bash
kgo myapp
# Shows pods with status like:
# myapp-api-123   0/1   CrashLoopBackOff
# myapp-web-456   0/1   Terminating
```

### hla

Lists broken or pending Helm releases (non-deployed status).

```bash
hla
```

**Example output:**
```
NAME        NAMESPACE    STATUS          CHART
myapp       production   pending-install myapp-1.2.3
oldapp      staging      failed          oldapp-2.1.0
```

### kaudit_nodes

Audits node roles in a specific cluster.

```bash
kaudit_nodes [cluster]
```

**Example:**
```bash
kaudit_nodes dev
# Output:
# 🖥️  dev nodes (6 total)
#       4 worker
#       2 control-plane
```

### kaudit_pods

Audits pod distribution in audit namespaces for a specific cluster.

```bash
kaudit_pods [cluster]
```

**Example:**
```bash
kaudit_pods dev
# Output:
# 🫛 dev pods (48 total)
#      12 testing
#      18 dev
#      18 stage
```

### kaudit

Runs a full audit across all configured clusters.

```bash
kaudit
```

**Example output:**
```
📊 Kubernetes Audit

🖥️  test nodes (8 total)
      6 worker
      2 control-plane

🫛 test pods (72 total)
     24 testing
     24 qa
     24 uat

🖥️  dev nodes (6 total)
      4 worker
      2 control-plane

🫛 dev pods (48 total)
     16 testing
     16 dev
     16 stage
```

## Workflow Examples

### Debugging a failing pod
```bash
# Switch to the right cluster
use-dev

# Find the pod
kgp myapp api

# Check if any pods are unhealthy
kgo myapp

# Describe the problematic pod
kdp myapp myapp-api-xyz

# Check logs
kgl myapp myapp-api-xyz

# Get a shell if needed
kgxx myapp myapp-api-xyz
```

### Deploying a new version
```bash
# Check current rollout status
kgr myapp myapp-api

# Watch pods
watch -n 1 'kgp myapp api'

# If issues, check logs on new pods
kgl myapp myapp-api-newpod-xyz
```

### Cluster health check
```bash
# Run full audit
kaudit

# Check node health
kgn

# Check pod distribution
kppn

# Check for broken Helm releases
hla
```

### Copying files to multiple pods
```bash
# Update config across all instances
kcp myapp api ./updated-config.yaml /app/config.yaml

# Verify it worked
kgx myapp api cat /app/config.yaml
```

### Interactive debugging session
```bash
# Get into a pod
kgxh myapp api /bin/bash

# Inside the pod:
# - Check environment variables: env
# - Test connectivity: curl http://other-service
# - Check file permissions: ls -la /app
# - View processes: ps aux
```

## Usage Tips

1. **Context Awareness**: Always verify your current context with `kubectl config current-context`
2. **Pod Filtering**: The `kgp [ns] [app]` pattern uses grep, so partial matches work
3. **Quick Pods**: For the first running pod, use `kgx` or `kgxh` instead of finding pod names manually
4. **Audit Regularly**: Run `kaudit` to get a quick overview of your cluster health
5. **Node Distribution**: Use `kppn` to ensure pods are evenly distributed across nodes
6. **Helm Health**: Run `hla` to catch stuck or failed Helm deployments
