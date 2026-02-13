#!/usr/bin/env bash
# 在两台 K8s 节点间配置免密 SSH（只需在任意一台执行一次，输入对方密码后即双向免密）
# 用法：在 l20-gpu-04 上执行  ./setup-node-ssh.sh l20-gpu-05
#       按提示输入 l20-gpu-05 的 root 密码一次，脚本会顺便把 05 的公钥拉回本机，实现 05→04 免密
# 可选：SSHPASS='对方密码' ./setup-node-ssh.sh l20-gpu-05  免交互
set -e
REMOTE="${1:?Usage: $0 <对方节点主机名或IP>}"
USER="${SSH_USER:-root}"

mkdir -p ~/.ssh
chmod 700 ~/.ssh
touch ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys

if [[ ! -f ~/.ssh/id_rsa ]]; then
  echo "生成 SSH 密钥（无密码）..."
  ssh-keygen -t rsa -b 4096 -f ~/.ssh/id_rsa -N ""
fi

echo "将本机公钥写入 ${USER}@${REMOTE}（需输入对方密码一次）..."
if [[ -n "${SSHPASS:-}" ]]; then
  sshpass -e ssh-copy-id -o StrictHostKeyChecking=accept-new "${USER}@${REMOTE}"
else
  ssh-copy-id -o StrictHostKeyChecking=accept-new "${USER}@${REMOTE}"
fi

echo "在对方节点生成密钥并拉回公钥，实现对方→本机免密..."
ssh -o BatchMode=yes "${USER}@${REMOTE}" "mkdir -p ~/.ssh; chmod 700 ~/.ssh; test -f ~/.ssh/id_rsa || ssh-keygen -t rsa -b 4096 -f ~/.ssh/id_rsa -N ''"
ssh "${USER}@${REMOTE}" "cat ~/.ssh/id_rsa.pub" >> ~/.ssh/authorized_keys

echo "测试双向免密："
ssh -o BatchMode=yes "${USER}@${REMOTE}" hostname && echo "  本机 -> ${REMOTE}  OK"
ssh -o BatchMode=yes "${USER}@${REMOTE}" "ssh -o StrictHostKeyChecking=no ${USER}@$(hostname) hostname" && echo "  ${REMOTE} -> 本机 OK"
echo "免密配置完成。"
