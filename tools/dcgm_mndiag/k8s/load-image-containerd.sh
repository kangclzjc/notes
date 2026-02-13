#!/usr/bin/env bash
# 在 K8s 节点上把 build-local.sh --save 导出的镜像导入 containerd（供 kubelet 使用）
# 若节点用 Docker 作容器运行时则用 load-image.sh；若用 containerd 则用本脚本
# 用法：把 dcgm-mndiag.tar.gz 拷到节点后执行 ./load-image-containerd.sh [路径]
set -e
TAR="${1:-dcgm-mndiag.tar.gz}"
if [[ ! -f "$TAR" ]]; then
  echo "Usage: $0 [path/to/dcgm-mndiag.tar.gz]"
  echo "File not found: $TAR"
  exit 1
fi
echo "Importing image into containerd (namespace k8s.io) from ${TAR}..."
gunzip -c "$TAR" | sudo ctr -n k8s.io images import -
echo "Done. Image dcgm-mndiag:latest is available for K8s on this node."
