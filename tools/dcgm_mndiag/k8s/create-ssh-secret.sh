#!/usr/bin/env bash
# 生成 SSH 密钥并创建 K8s Secret，用于 dcgm-mndiag 两节点免密
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KEYS_DIR="${SCRIPT_DIR}/../ssh_keys"
NAMESPACE="${NAMESPACE:-dcgm-mndiag}"

mkdir -p "$KEYS_DIR"
if [[ ! -f "${KEYS_DIR}/id_rsa" ]]; then
  echo "Generating SSH key pair in ${KEYS_DIR} (no passphrase for mndiag)..."
  ssh-keygen -t rsa -b 4096 -f "${KEYS_DIR}/id_rsa" -N ""
fi

echo "Creating secret dcgm-mndiag-ssh in namespace ${NAMESPACE}..."
kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
kubectl create secret generic dcgm-mndiag-ssh \
  --namespace="$NAMESPACE" \
  --from-file=id_rsa="${KEYS_DIR}/id_rsa" \
  --from-file=id_rsa.pub="${KEYS_DIR}/id_rsa.pub" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "Done. Deploy with: kubectl apply -f ${SCRIPT_DIR}/"
