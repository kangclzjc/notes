# DCGM mndiag Docker 两节点部署（免密 SSH）

两种用法：**同一台机两个容器**（docker-compose）、**两台物理机**（run-two-nodes.sh）。

## 前提

- 已构建镜像：在 `tools/dcgm_mndiag` 目录 `docker build -t dcgm-mndiag:latest .`
- 主机已安装 NVIDIA Container Toolkit，`docker run --gpus all` 可用

---

## 方式一：同一台主机（docker-compose）

两台“节点”都是本机的两个容器，通过 compose 网络互通，用服务名 `head` / `worker` 做 hostList。

### 1. 生成 SSH 密钥（免密）

```bash
cd tools/dcgm_mndiag/docker/scripts
./setup-ssh-keys.sh
```

会在 `docker/ssh_keys/` 下生成 `id_rsa`、`id_rsa.pub`、`authorized_keys`。

### 2. 启动

```bash
cd tools/dcgm_mndiag/docker
# 先起 worker，再起 head（head 会跑一次 mndiag 然后退出）
docker compose up -d worker
sleep 5
docker compose up head
```

看 head 输出：`docker compose logs -f head`。

### 3. 再次跑一次

```bash
docker compose up head
```

---

## 方式二：两台物理机

- **节点1**：跑 head 容器（发起 mndiag）
- **节点2**：跑 worker 容器（sshd + nv-hostengine），并把容器 22 映射到主机端口（默认 2222），避免和主机 ssh 冲突

两台机器需要能互相访问（用 IP 或主机名），且 **ssh_keys 目录要在两台机器上一致**（同一路径或 NFS）。

### 1. 生成密钥并同步 ssh_keys

在**任意一台**机器上：

```bash
cd tools/dcgm_mndiag/docker/scripts
./setup-ssh-keys.sh
```

把整个 `tools/dcgm_mndiag/docker` 目录拷到另一台机器**相同路径**（或两台都挂载同一 NFS）。

### 2. 在节点2（worker 所在机器）启动 worker

```bash
cd tools/dcgm_mndiag/docker
./run-two-nodes.sh worker
```

默认把容器 22 映射到主机 **2222**。改端口：`WORKER_SSH_PORT=3022 ./run-two-nodes.sh worker`。

### 3. 在节点1（head 所在机器）启动 head

```bash
cd tools/dcgm_mndiag/docker
NODE2_IP=<节点2的IP> ./run-two-nodes.sh head
```

脚本会在 head 容器里配置 `~/.ssh/config`，让 SSH 到节点2 时使用 2222 端口，连到 worker 容器的 sshd；hostList 为 `localhost;NODE2_IP`（head 用 localhost，worker 用节点2 的 IP，DCGM 通过节点2 的 5555 连 worker 的 hostengine）。

---

## 免密说明

- mndiag 要求 **所有参与节点之间** 都能免密 SSH（同一账号，这里是 root）。
- 做法：用同一对密钥，**head 放私钥**，**head 和 worker 的 `authorized_keys` 里都放同一公钥**（head 自连也需要）。
- 密钥**不要设密码**，否则 nv-hostengine 子进程里无法用 ssh-agent，会失败。
