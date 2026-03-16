#!/bin/bash
set -euo pipefail

################################################################################
# Teardown — Remove GitHub Actions Self-Hosted Runner from K3s
################################################################################

NAMESPACE="actions-runner-system"
export KUBECONFIG=${KUBECONFIG:-/etc/rancher/k3s/k3s.yaml}

echo "🧹 Tearing down GitHub Actions Runner infrastructure..."
echo ""

# Uninstall all runner scale sets in the namespace
RELEASES=$(helm list -n "$NAMESPACE" --short 2>/dev/null || true)
if [ -n "$RELEASES" ]; then
  for RELEASE in $RELEASES; do
    echo "🗑️  Uninstalling $RELEASE..."
    helm uninstall "$RELEASE" -n "$NAMESPACE" --wait --timeout 60s 2>/dev/null || true
    echo "✅ $RELEASE removed"
  done
else
  echo "⏭️  No Helm releases found, skipping"
fi

# Delete namespace (with timeout)
if kubectl get ns "$NAMESPACE" &>/dev/null 2>/dev/null; then
  echo "🗑️  Deleting namespace $NAMESPACE..."
  kubectl delete ns "$NAMESPACE" --timeout=60s 2>/dev/null || {
    echo "⚠️  Namespace stuck, force-removing finalizers..."
    kubectl get ns "$NAMESPACE" -o json | jq '.spec.finalizers = []' | \
      kubectl replace --raw "/api/v1/namespaces/$NAMESPACE/finalize" -f - > /dev/null 2>&1 || true
    echo "✅ Namespace force-deleted"
  }
  echo "✅ Namespace deleted"
fi

# Delete PersistentVolume (PVC is deleted with namespace)
if kubectl get pv runner-cache-pv &>/dev/null 2>/dev/null; then
  echo "🗑️  Deleting cache PersistentVolume..."
  kubectl delete pv runner-cache-pv
  echo "✅ PV removed (cache data at /data/runner-cache is preserved)"
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
echo "Note: Cache data at /data/runner-cache is preserved. Run 'sudo rm -rf /data/runner-cache' to delete it."
