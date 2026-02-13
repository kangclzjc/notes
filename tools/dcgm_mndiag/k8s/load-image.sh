#!/usr/bin/env bash
# 在 K8s 节点上加载 build-local.sh --save 导出的镜像，加载后镜像名为 dcgm-mndiag:latest，与 deployment 一致
# 用法：把 dcgm-mndiag.tar.gz 拷到节点后执行 ./load-image.sh [路径]
#   ./load-image.sh                    # 当前目录下的 dcgm-mndiag.tar.gz
#   ./load-image.sh /tmp/dcgm-mndiag.tar.gz
set -e
TAR="${1:-dcgm-mndiag.tar.gz}"
if [[ ! -f "$TAR" ]]; then
  echo "Usage: $0 [path/to/dcgm-mndiag.tar.gz]"
  echo "File not found: $TAR"
  exit 1
fi
echo "Loading image from ${TAR}..."
gunzip -c "$TAR" | docker load
echo "Done. Image dcgm-mndiag:latest is ready for deploy."
