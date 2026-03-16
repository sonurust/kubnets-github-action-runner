# Kubernetes GitHub Actions Self-Hosted Runner (Auto-Scaling)

Auto-scaling GitHub Actions self-hosted runners on **K3s** using **ARC v2** (Actions Runner Controller) with **Runner Scale Sets**.

## Architecture

```
GitHub Actions Queue
        │
        ▼  (Job Available signal)
┌───────────────────┐
│  Listener Pod     │  ← Persistent connection to GitHub
│  (k8s-runner)     │
└───────┬───────────┘
        │  (scales up)
        ▼
┌───────────────────┐
│  ARC Controller   │  ← Creates ephemeral runner pods
│                   │
└───────┬───────────┘
        │
        ▼
┌───────────────────┐
│  Runner Pod       │  ← Runs the job, then self-destructs
│  (ephemeral)      │
└───────────────────┘
```

## Quick Start

```bash
# One-command setup
chmod +x setup.sh && ./setup.sh
```

## How It Works

| Feature | Details |
|---------|---------|
| **Runner name** | `k8s-runner` |
| **Repository** | `sonurust/grocery-project` |
| **Min runners** | 0 (zero cost when idle) |
| **Max runners** | 15 (concurrent) |
| **Scaling** | GitHub-native via Runner Scale Sets |

### Auto-Scaling Flow

1. You push code → GitHub workflow triggers with `runs-on: k8s-runner`
2. GitHub signals the ARC Listener Pod
3. ARC Controller creates an ephemeral Runner Pod
4. Runner picks up the job, executes it
5. Runner self-deregisters and pod is deleted

## Use in Your Workflows

```yaml
jobs:
  build:
    runs-on: k8s-runner   # ← Use this label
    steps:
      - uses: actions/checkout@v4
      - run: echo "Running on K8s!"
```

## Dependency Cache (External Disk)

The external disk (`/dev/sdb1`, 1.1TB) is mounted at `/data/runner-cache` and exposed
to runner pods as `/opt/cache` via a PersistentVolume. This eliminates repeated downloads
of large SDKs across jobs and workflow runs.

| Cache Directory | Env Variable | Contents |
|-----------------|-------------|----------|
| `/opt/cache/flutter` | `FLUTTER_ROOT` | Flutter SDK |
| `/opt/cache/pub-cache` | `PUB_CACHE` | Dart packages |
| `/opt/cache/gradle` | `GRADLE_USER_HOME` | Gradle deps & wrappers |
| `/opt/cache/android-sdk` | `ANDROID_HOME` | Android SDK components |

**First run** downloads everything (~5–10 min). **Subsequent runs** reuse the cache (near-instant).

To reset the cache:
```bash
sudo rm -rf /data/runner-cache/*
```

## Commands

```bash
# Check runner pods
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
kubectl get pods -n actions-runner-system

# View logs
kubectl logs -n actions-runner-system -l app=k8s-runner

# Teardown everything
chmod +x teardown.sh && ./teardown.sh
```

## Prerequisites

- K3s (Kubernetes)
- Helm
- `gh` CLI (authenticated)
- Docker
