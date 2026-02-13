#!/usr/bin/env bash
# 构建 dcgm-mndiag 镜像，并可选：导入 Kind/Minikube 或导出 tar 供其他节点使用
# K8s 部署已配置为使用本地镜像 image: dcgm-mndiag:latest + imagePullPolicy: Never
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGE="${IMAGE:-dcgm-mndiag:latest}"

usage() {
  echo "Usage: $0 [OPTIONS]"
  echo "  Build image and optionally load/save for local K8s."
  echo ""
  echo "Options:"
  echo "  --kind         After build, load into Kind cluster (kind load docker-image ...)"
  echo "  --minikube     After build, load into Minikube (minikube image load ...)"
  echo "  --save [DIR]   After build, save to dcgm-mndiag.tar.gz (default: current dir); copy to other nodes and docker load"
  echo "  -h, --help     Show this help"
  echo ""
  echo "Env: IMAGE=${IMAGE}  DCGM_VERSION  CUDA_TOOLKIT_VERSION  CUDA_UBUNTU_REPO (passed to docker build)"
  exit 0
}

LOAD_KIND=false
LOAD_MINIKUBE=false
SAVE_TAR=false
SAVE_DIR="."

while [[ $# -gt 0 ]]; do
  case "$1" in
    --kind)       LOAD_KIND=true; shift ;;
    --minikube)   LOAD_MINIKUBE=true; shift ;;
    --save)       SAVE_TAR=true; shift
                  if [[ -n "${1:-}" && "$1" != -* ]]; then SAVE_DIR="$1"; shift; fi
                  ;;
    -h|--help)    usage ;;
    *)            echo "Unknown option: $1"; usage ;;
  esac
done

echo "=== Building ${IMAGE} in ${SCRIPT_DIR} ==="
docker build -t "$IMAGE" "$SCRIPT_DIR"

if [[ "$LOAD_KIND" == "true" ]]; then
  echo "=== Loading into Kind ==="
  kind load docker-image "$IMAGE"
fi

if [[ "$LOAD_MINIKUBE" == "true" ]]; then
  echo "=== Loading into Minikube ==="
  minikube image load "$IMAGE"
fi

if [[ "$SAVE_TAR" == "true" ]]; then
  SAVE_PATH="${SAVE_DIR}/dcgm-mndiag.tar.gz"
  echo "=== Saving to ${SAVE_PATH} ==="
  mkdir -p "$SAVE_DIR"
  docker save "$IMAGE" | gzip -c > "$SAVE_PATH"
  echo "On other node: gunzip -c dcgm-mndiag.tar.gz | docker load"
fi

echo ""
echo "Done. Image: ${IMAGE}"
echo "K8s 已使用本地镜像（imagePullPolicy: Never），在各运行 Pod 的节点上存在此镜像后执行: cd k8s && ./deploy.sh"
