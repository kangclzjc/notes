#!/usr/bin/env bash
# 一键部署 dcgm-mndiag（namespace + SSH Secret + head + worker + services）
# 使用前确保各 GPU 节点上已有镜像 dcgm-mndiag:latest（见 README「使用本地构建的镜像」）
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NAMESPACE="${NAMESPACE:-dcgm-mndiag}"
WAIT_READY="${WAIT_READY:-true}"   # 是否等待 Pod 就绪，设为 false 可跳过

export NAMESPACE
echo "=== dcgm-mndiag 一键部署 (namespace: ${NAMESPACE}) ==="

# 1. SSH 密钥与 Secret
echo "[1/4] 创建 SSH 密钥与 Secret..."
"${SCRIPT_DIR}/create-ssh-secret.sh"

# 2. Namespace（create-ssh-secret 已创建，这里再 apply 一次保证存在）
echo "[2/4] 应用 namespace..."
kubectl apply -f "${SCRIPT_DIR}/namespace.yaml"

# 3. 应用部署与服务
echo "[3/4] 应用 head / worker / services..."
kubectl apply -f "${SCRIPT_DIR}/head-deployment.yaml"
kubectl apply -f "${SCRIPT_DIR}/worker-deployment.yaml"
kubectl apply -f "${SCRIPT_DIR}/services.yaml"

# 4. 等待就绪
if [[ "$WAIT_READY" == "true" ]]; then
  echo "[4/4] 等待 Pod 就绪..."
  kubectl wait --namespace="$NAMESPACE" --for=condition=available --timeout=120s deployment/dcgm-mndiag-head deployment/dcgm-mndiag-worker 2>/dev/null || {
    echo "  (部分 Pod 可能仍在启动，可用 kubectl get pod -n ${NAMESPACE} 查看)"
  }
else
  echo "[4/4] 跳过等待 (WAIT_READY=false)"
fi

echo ""
echo "=== 部署完成 ==="
kubectl get pod -n "$NAMESPACE" -l app=dcgm-mndiag
echo ""
echo "进入 head 测试免密与单机命令："
echo "  kubectl exec -it -n ${NAMESPACE} deployment/dcgm-mndiag-head -- bash"
echo "  # 在 head 里： ssh dcgm-mndiag-worker hostname   ssh dcgm-mndiag-worker nvidia-smi   dcgmi discovery -n"
