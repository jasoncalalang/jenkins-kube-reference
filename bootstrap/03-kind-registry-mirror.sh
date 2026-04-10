#!/usr/bin/env bash
#
# Retrofit a containerd registry mirror on every kind node so that images
# pushed to the in-cluster registry (NodePort :30500) can be pulled from
# workload pods via the short name `localhost:5000/<image>`.
#
# Why this is needed: kind nodes run containerd, and containerd's image pull
# path uses its own registry configuration — it does NOT consult cluster
# Services. Without this mirror, Deployments that reference
# `localhost:5000/foo` will fail with ImagePullBackOff because `localhost`
# inside the kind node points at the node itself, not the cluster registry.
#
# This script is idempotent and safe to re-run.

set -euo pipefail

echo "==> Discovering kind node containers"
mapfile -t NODES < <(docker ps --filter label=io.x-k8s.kind.cluster --format '{{.Names}}' || true)

if [[ ${#NODES[@]} -eq 0 ]]; then
  echo "==> No kind node containers found — nothing to do."
  echo "    (This script is a no-op on non-kind clusters.)"
  exit 0
fi

FIRST_NODE="${NODES[0]}"
echo "==> Found ${#NODES[@]} kind node(s). Using '${FIRST_NODE}' as registry host."

HOSTS_DIR='/etc/containerd/certs.d/localhost:5000'
HOSTS_TOML_CONTENT=$(cat <<EOF
server = "http://localhost:5000"

[host."http://${FIRST_NODE}:30500"]
  capabilities = ["pull", "resolve"]
  skip_verify = true
EOF
)

for node in "${NODES[@]}"; do
  echo "==> Configuring containerd mirror on node '${node}'"
  docker exec "${node}" mkdir -p "${HOSTS_DIR}"
  docker exec -i "${node}" sh -c "cat > '${HOSTS_DIR}/hosts.toml'" <<< "${HOSTS_TOML_CONTENT}"
  echo "    wrote ${HOSTS_DIR}/hosts.toml"
  echo "==> Restarting containerd on '${node}'"
  docker exec "${node}" systemctl restart containerd
done

echo "==> All ${#NODES[@]} kind node(s) now mirror localhost:5000 → ${FIRST_NODE}:30500"
