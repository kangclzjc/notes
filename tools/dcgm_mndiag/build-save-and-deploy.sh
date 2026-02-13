#!/usr/bin/env bash
# 一键：构建镜像 → save 到本地 → 在本机 load 镜像 → 部署到 K8s
# 多节点时：需在其它节点用 load-image.sh（Docker 运行时）或 load-image-containerd.sh（containerd）加载镜像
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TAR_PATH="${SCRIPT_DIR}/dcgm-mndiag.tar.gz"
cd "$SCRIPT_DIR"

echo "=== 1. Build & save ==="
./build-local.sh --save

echo ""
echo "=== 2. Load image 到本机（供 K8s 或 docker 使用）==="
if [[ -f "$TAR_PATH" ]]; then
  gunzip -c "$TAR_PATH" | docker load
  echo "已 load: dcgm-mndiag:latest"
else
  echo "未找到 ${TAR_PATH}，跳过 load（镜像已在 build 后存在于 Docker）"
fi

echo ""
echo "=== 3. Deploy to K8s ==="
cd "$SCRIPT_DIR/k8s"
./deploy.sh

echo ""
echo "若 head/worker 跑在其它节点，请先在各节点加载镜像："
echo "  Docker 运行时: ./load-image.sh dcgm-mndiag.tar.gz"
echo "  containerd 运行时: ./load-image-containerd.sh dcgm-mndiag.tar.gz"
