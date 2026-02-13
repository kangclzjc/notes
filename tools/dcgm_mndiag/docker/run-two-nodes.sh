#!/usr/bin/env bash
# 在两台物理机上跑 mndiag：节点1 跑 head，节点2 跑 worker，需免密 SSH 与互通网络
#
# 用法：
#   在节点2（worker）上先执行：./run-two-nodes.sh worker
#   在节点1（head）上执行：NODE2_IP=节点2的IP ./run-two-nodes.sh head
#
# 前提：两台机器能互相访问（IP 或主机名），且先在一台机器上运行 setup-ssh-keys.sh，
#       把 docker/ssh_keys 目录拷到两台机器相同路径（或通过 NFS 共享）。
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KEYS_DIR="${SCRIPT_DIR}/ssh_keys"
IMAGE="${IMAGE:-dcgm-mndiag:latest}"

# 节点2 上容器端口映射到主机，避免与主机 22/5555 冲突
WORKER_SSH_PORT="${WORKER_SSH_PORT:-2222}"
WORKER_DCGM_PORT="${WORKER_DCGM_PORT:-5555}"

if [[ ! -d "$KEYS_DIR" ]] || [[ ! -f "${KEYS_DIR}/id_rsa" ]]; then
  echo "Run setup-ssh-keys.sh first and ensure ssh_keys/ exists with id_rsa and id_rsa.pub"
  exit 1
fi

role="${1:-}"
if [[ "$role" == "worker" ]]; then
  echo "Starting worker (sshd + nv-hostengine), host ports SSH=${WORKER_SSH_PORT} DCGM=${WORKER_DCGM_PORT}..."
  docker run -d --rm --name dcgm-mndiag-worker \
    --gpus all \
    -p "${WORKER_SSH_PORT}:22" \
    -p "${WORKER_DCGM_PORT}:5555" \
    -v "${KEYS_DIR}/authorized_keys:/root/.ssh/authorized_keys:ro" \
    "$IMAGE" \
    /bin/bash -c 'mkdir -p /root/.ssh && chmod 700 /root/.ssh && chmod 600 /root/.ssh/authorized_keys && /usr/sbin/sshd && exec nv-hostengine -f'
  echo "Worker running. On head node run: NODE2_IP=<this-node-ip> $0 head"
  exit 0
fi

if [[ "$role" != "head" ]]; then
  echo "Usage: $0 head | worker"
  echo "  On node2 (worker): $0 worker"
  echo "  On node1 (head): NODE2_IP=<worker-node-ip> $0 head"
  exit 1
fi

NODE2_IP="${NODE2_IP:?set NODE2_IP (worker 所在节点 IP)}"

# Head 容器内：localhost 即本容器（head），worker 在 NODE2_IP；SSH 到 NODE2_IP 用端口 WORKER_SSH_PORT
mkdir -p "${KEYS_DIR}/head_ssh"
cat > "${KEYS_DIR}/head_ssh/config" << EOF
Host ${NODE2_IP}
  Port ${WORKER_SSH_PORT}
  StrictHostKeyChecking no
  UserKnownHostsFile /root/.ssh/known_hosts
EOF

# hostList：第一节点 localhost，第二节点 NODE2_IP（若 worker 映射了非默认 5555 则加 :端口）
WORKER_DCGM_HOST="${NODE2_IP}"
[[ "${WORKER_DCGM_PORT}" != "5555" ]] && WORKER_DCGM_HOST="${NODE2_IP}:${WORKER_DCGM_PORT}"
echo "Starting head: hostList localhost;${WORKER_DCGM_HOST}, worker SSH port ${WORKER_SSH_PORT}..."
docker run --rm --name dcgm-mndiag-head \
  --gpus all \
  -v "${KEYS_DIR}/id_rsa:/root/.ssh/id_rsa:ro" \
  -v "${KEYS_DIR}/id_rsa.pub:/root/.ssh/id_rsa.pub:ro" \
  -v "${KEYS_DIR}/head_ssh/config:/root/.ssh/config:ro" \
  -e DCGM_MNDIAG_MPIRUN_PATH=/usr/bin/mpirun \
  "$IMAGE" \
  /bin/bash -c '
    chmod 700 /root/.ssh
    chmod 600 /root/.ssh/id_rsa /root/.ssh/id_rsa.pub /root/.ssh/config
    cp /root/.ssh/id_rsa.pub /root/.ssh/authorized_keys
    chmod 600 /root/.ssh/authorized_keys
    /usr/sbin/sshd
    nv-hostengine -b -f 2>/dev/null || true
    sleep 2
    exec dcgmi mndiag --hostList "localhost;'"${WORKER_DCGM_HOST}"'" --hostEngineAddress localhost -j
  '
