#!/bin/bash
set -euo pipefail

################################################################################
# GitHub Actions Self-Hosted Runner on K3s — One-Command Setup
# Uses gh CLI for auth, ARC v2 (Runner Scale Sets) for auto-scaling
################################################################################

REPO_URL="https://github.com/sonurust/grocery-project"
NAMESPACE="actions-runner-system"
RUNNER_NAME="k8s-runner"
MIN_RUNNERS=0    # Scale to zero when idle
MAX_RUNNERS=15   # Max concurrent runners

echo "🚀 GitHub Actions Self-Hosted Runner Setup"
echo "==========================================="
echo "Repo:        $REPO_URL"
echo "Namespace:   $NAMESPACE"
echo "Runner name: $RUNNER_NAME"
echo "Scaling:     $MIN_RUNNERS → $MAX_RUNNERS"
echo ""

# ─── Prerequisite Checks ─────────────────────────────────────────────────────

check_cmd() {
  if ! command -v "$1" &>/dev/null; then
    echo "❌ $1 not found. Please install it first."
    exit 1
  fi
}

check_cmd kubectl
check_cmd helm
check_cmd gh

# ─── Get GitHub Token from gh CLI ─────────────────────────────────────────────

echo "🔑 Getting GitHub token from gh CLI..."

# When running with sudo, gh config lives in the real user's home, not /root
REAL_HOME="${SUDO_USER:+/home/$SUDO_USER}"
REAL_HOME="${REAL_HOME:-$HOME}"

if command -v gh &>/dev/null; then
  # Try 'gh auth token' first (works on newer gh versions)
  if GITHUB_TOKEN=$(HOME="$REAL_HOME" gh auth token 2>/dev/null) && [ -n "$GITHUB_TOKEN" ]; then
    :  # success
  elif [ -f "$REAL_HOME/.config/gh/hosts.yml" ]; then
    GITHUB_TOKEN=$(grep 'oauth_token' "$REAL_HOME/.config/gh/hosts.yml" | head -1 | awk '{print $2}')
  fi
fi

if [ -z "${GITHUB_TOKEN:-}" ]; then
  echo "❌ Could not get GitHub token."
  echo "   Run 'gh auth login' first (as your regular user, not root)."
  exit 1
fi
echo "✅ GitHub token retrieved"

# ─── Set KUBECONFIG ───────────────────────────────────────────────────────────

export KUBECONFIG=${KUBECONFIG:-/etc/rancher/k3s/k3s.yaml}
echo "📋 Using KUBECONFIG: $KUBECONFIG"

# Fix permissions so non-root users can also use kubectl
if [ -f "$KUBECONFIG" ] && [ "$(id -u)" -eq 0 ]; then
  chmod 644 "$KUBECONFIG" 2>/dev/null || true
fi

# Verify cluster
if ! kubectl get nodes &>/dev/null; then
  echo "❌ Cannot connect to K3s cluster. Is k3s running?"
  echo "   Start it with: sudo systemctl start k3s"
  exit 1
fi
echo "✅ K3s cluster connected"

# ─── Install cert-manager ────────────────────────────────────────────────────

if kubectl get ns cert-manager &>/dev/null 2>/dev/null; then
  echo "✅ cert-manager already installed"
else
  echo "📦 Installing cert-manager..."
  kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.17.2/cert-manager.yaml
  echo "⏳ Waiting for cert-manager to be ready..."
  kubectl wait --for=condition=Available deployment --all -n cert-manager --timeout=120s
  echo "✅ cert-manager ready"
fi

# ─── Create GitHub Token Secret ──────────────────────────────────────────────

echo "🔐 Creating GitHub token secret..."
kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
kubectl create secret generic github-token \
  --namespace "$NAMESPACE" \
  --from-literal=github_token="$GITHUB_TOKEN" \
  --dry-run=client -o yaml | kubectl apply -f -
echo "✅ GitHub token secret created"

# ─── Apply Cache PV & PVC ────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
echo "💾 Creating dependency cache PV & PVC on /data/runner-cache..."
kubectl apply -f "$SCRIPT_DIR/k8s/runner-cache-pv.yaml"
echo "✅ Cache PV & PVC ready"

# ─── Install ARC Controller ──────────────────────────────────────────────────

if helm list -n "$NAMESPACE" | grep -q "^arc"; then
  echo "✅ ARC controller already installed"
else
  echo "📦 Installing ARC v2 controller..."
  helm install arc \
    --namespace "$NAMESPACE" \
    --create-namespace \
    oci://ghcr.io/actions/actions-runner-controller-charts/gha-runner-scale-set-controller
  echo "✅ ARC controller installed"
fi

# ─── Deploy Runner Scale Set ─────────────────────────────────────────────────

echo "📦 Deploying runner scale set..."
helm upgrade --install grocery-runner \
  --namespace "$NAMESPACE" \
  -f "$SCRIPT_DIR/k8s/values.yaml" \
  --set githubConfigUrl="$REPO_URL" \
  --set githubConfigSecret=github-token \
  --set minRunners="$MIN_RUNNERS" \
  --set maxRunners="$MAX_RUNNERS" \
  --set runnerScaleSetName="$RUNNER_NAME" \
  oci://ghcr.io/actions/actions-runner-controller-charts/gha-runner-scale-set
echo "✅ Runner scale set deployed"

# ─── Verify ──────────────────────────────────────────────────────────────────

echo ""
echo "⏳ Waiting for pods to be ready..."
sleep 10
kubectl get pods -n "$NAMESPACE"

echo ""
echo "🎉 Setup Complete!"
echo "==========================================="
echo ""
echo "Your self-hosted runner '$RUNNER_NAME' is now active."
echo ""
echo "Use it in your GitHub Actions workflows with:"
echo ""
echo "  jobs:"
echo "    build:"
echo "      runs-on: $RUNNER_NAME"
echo ""
echo "Auto-scaling: $MIN_RUNNERS (idle) → $MAX_RUNNERS (max concurrent)"
echo "Runners are ephemeral — created per job, deleted after completion."
echo ""
echo "Check runner status at:"
echo "  ${REPO_URL}/settings/actions/runners"
