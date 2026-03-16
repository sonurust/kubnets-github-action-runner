#!/bin/bash
set -euo pipefail

################################################################################
# Teardown — Remove GitHub Actions Self-Hosted Runner from K3s
################################################################################

NAMESPACE="actions-runner-system"
export KUBECONFIG=${KUBECONFIG:-/etc/rancher/k3s/k3s.yaml}

echo "🧹 Tearing down GitHub Actions Runner infrastructure..."
echo ""

# Uninstall runner scale set
if helm list -n "$NAMESPACE" 2>/dev/null | grep -q "^grocery-runner"; then
  echo "🗑️  Uninstalling runner scale set..."
  helm uninstall grocery-runner -n "$NAMESPACE"
  echo "✅ Runner scale set removed"
else
  echo "⏭️  Runner scale set not found, skipping"
fi

# Uninstall ARC controller
if helm list -n "$NAMESPACE" 2>/dev/null | grep -q "^arc"; then
  echo "🗑️  Uninstalling ARC controller..."
  helm uninstall arc -n "$NAMESPACE"
  echo "✅ ARC controller removed"
else
  echo "⏭️  ARC controller not found, skipping"
fi

# Delete namespace
if kubectl get ns "$NAMESPACE" &>/dev/null 2>/dev/null; then
  echo "🗑️  Deleting namespace $NAMESPACE..."
  kubectl delete ns "$NAMESPACE"
  echo "✅ Namespace deleted"
fi

# Optionally remove cert-manager
read -p "Also remove cert-manager? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
  echo "🗑️  Removing cert-manager..."
  kubectl delete -f https://github.com/cert-manager/cert-manager/releases/download/v1.17.2/cert-manager.yaml 2>/dev/null || true
  echo "✅ cert-manager removed"
fi

echo ""
echo "🏁 Teardown complete!"
