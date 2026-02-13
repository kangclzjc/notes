#!/usr/bin/env bash
# 生成用于 mndiag 免密 SSH 的密钥（无密码），供 Docker 两节点使用
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KEYS_DIR="${SCRIPT_DIR}/../ssh_keys"

mkdir -p "$KEYS_DIR"
if [[ ! -f "${KEYS_DIR}/id_rsa" ]]; then
  echo "Generating SSH key in ${KEYS_DIR} (no passphrase for mndiag)..."
  ssh-keygen -t rsa -b 4096 -f "${KEYS_DIR}/id_rsa" -N ""
fi
# 用于 worker 的 authorized_keys
cp -f "${KEYS_DIR}/id_rsa.pub" "${KEYS_DIR}/authorized_keys"
echo "Done. authorized_keys created from id_rsa.pub"
