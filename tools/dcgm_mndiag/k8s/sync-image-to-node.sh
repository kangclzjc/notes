#!/usr/bin/env bash
# 在已配置免密 SSH 后，把镜像 tar 和 containerd 加载脚本拷到另一节点并加载
# 用法：在 l20-gpu-04 上执行  ./sync-image-to-node.sh l20-gpu-05
# 依赖：已对 l20-gpu-05 免密（见 setup-node-ssh.sh）
set -e
REMOTE="${1:?Usage: $0 <节点主机名或IP>}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TAR="${SCRIPT_DIR}/../dcgm-mndiag.tar.gz"

if [[ ! -f "$TAR" ]]; then
  echo "未找到 ${TAR}，请先 build --save"
  exit 1
fi

echo "拷贝镜像与加载脚本到 ${REMOTE}..."
scp -o StrictHostKeyChecking=accept-new "$TAR" "${SCRIPT_DIR}/load-image-containerd.sh" "root@${REMOTE}:/tmp/"

echo "在 ${REMOTE} 上加载镜像到 containerd..."
ssh "root@${REMOTE}" "chmod +x /tmp/load-image-containerd.sh && /tmp/load-image-containerd.sh /tmp/dcgm-mndiag.tar.gz && rm -f /tmp/dcgm-mndiag.tar.gz /tmp/load-image-containerd.sh"

echo "完成。${REMOTE} 已具备镜像 dcgm-mndiag:latest"
