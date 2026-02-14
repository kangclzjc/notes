# DCGM mndiag K8s 部署（两节点 + 免密 SSH）

在两台 GPU 节点上跑 DCGM 多节点诊断，通过 K8s 部署 head + worker 两个 Pod，并配置免密 SSH。

## 前提

- 集群已安装 NVIDIA device plugin（`nvidia.com/gpu` 可用）
- 两台节点各有 GPU，且希望分别调度 head / worker 到不同节点时，可在 deployment 里设置 `nodeName` 或 `nodeSelector`

## 一键部署（推荐）

**先确保各 GPU 节点上已有镜像**（见下方「使用本地构建的镜像」），然后：

```bash
cd tools/dcgm_mndiag/k8s
chmod +x deploy.sh
./deploy.sh
```

脚本会：生成 SSH 密钥并创建 Secret → 应用 namespace / head / worker / services → 等待 Pod 就绪。不想等待可 `WAIT_READY=false ./deploy.sh`。指定命名空间：`NAMESPACE=my-ns ./deploy.sh`。

### 两节点（l20-gpu-04 / l20-gpu-05）免密 + 分布部署

**当前方案（hostNetwork）：** 已改为 **hostNetwork**，head 与 worker 使用节点网络，走**节点间 SSH**（与「容器外免密」一致）。Worker 的 sshd 监听 **2222** 避免与节点 22 冲突；head 通过 `NODE_WORKER_IP`（默认 10.6.131.36）和端口 2222 连 worker。在 head 里执行 `ssh worker` 即可免密到 worker。

若需改 worker 节点 IP，在 `head-deployment.yaml` 中修改 env `NODE_WORKER_IP` 并重新 apply。

原「两节点 Pod 网络」步骤（供参考，当前集群 Pod 间 22 不通故未用）：

1. **两机免密**（在 l20-gpu-04 上执行，按提示输入 l20-gpu-05 的 root 密码一次）：
   ```bash
   cd tools/dcgm_mndiag/k8s
   ./setup-node-ssh.sh l20-gpu-05
   ```
   或免交互：`SSHPASS='l20-gpu-05的root密码' ./setup-node-ssh.sh l20-gpu-05`

2. **把镜像同步到 l20-gpu-05 并加载到 containerd**（仍在 l20-gpu-04 上）：
   ```bash
   ./sync-image-to-node.sh l20-gpu-05
   ```

3. **部署**（l20-gpu-04 上已有镜像时可直接执行）：
   ```bash
   ./deploy.sh
   ```

---

## 1. 生成 SSH 密钥并创建 Secret（免密，一键脚本已包含）

```bash
cd tools/dcgm_mndiag/k8s
./create-ssh-secret.sh
```

或手动：

```bash
mkdir -p tools/dcgm_mndiag/ssh_keys
ssh-keygen -t rsa -b 4096 -f tools/dcgm_mndiag/ssh_keys/id_rsa -N ""

kubectl create namespace dcgm-mndiag --dry-run=client -o yaml | kubectl apply -f -
kubectl create secret generic dcgm-mndiag-ssh -n dcgm-mndiag \
  --from-file=id_rsa=tools/dcgm_mndiag/ssh_keys/id_rsa \
  --from-file=id_rsa.pub=tools/dcgm_mndiag/ssh_keys/id_rsa.pub
```

## 2. 使用本地构建的镜像

Pod 默认使用 `image: dcgm-mndiag:latest` 且 `imagePullPolicy: Never`，即**只用节点上已有的镜像、不拉取**。YAML 无需修改。

**步骤：**

1. **构建镜像（推荐用脚本）：**
   ```bash
   cd tools/dcgm_mndiag
   ./build-local.sh              # 仅构建
   ./build-local.sh --kind       # 构建并导入 Kind
   ./build-local.sh --minikube   # 构建并导入 Minikube
   ./build-local.sh --save       # 构建并导出 dcgm-mndiag.tar.gz，拷到其他节点后 docker load
   ```
   或手动：`docker build -t dcgm-mndiag:latest .`

2. **让运行 Pod 的节点上都有这个镜像（任选一种）：**
   - **两节点各自构建**：在将要跑 head 的节点上执行一次上面的 `docker build`，在将要跑 worker 的节点上也执行一次（或把 Dockerfile 拷过去再 build）。
   - **用 --save 导出的 tar（推荐）**：见下方「用 save 的镜像部署到 K8s」。
   - **Kind：** `kind load docker-image dcgm-mndiag:latest`
   - **Minikube：** `minikube image load dcgm-mndiag:latest`

3. **部署时不要改 YAML**：保持 `image: dcgm-mndiag:latest` 和 `imagePullPolicy: Never` 即可。

### 用 --save 的镜像部署到 K8s（不改 YAML）

`build-local.sh --save` 导出的 `dcgm-mndiag.tar.gz` 里就是 `dcgm-mndiag:latest`，加载后名字不变，**无需改 deployment 的 image**。

1. **构建并导出：**（在能 build 的机器上）
   ```bash
   cd tools/dcgm_mndiag
   ./build-local.sh --save        # 得到 dcgm-mndiag.tar.gz
   # 或 ./build-local.sh --save /tmp  得到 /tmp/dcgm-mndiag.tar.gz
   ```

2. **在会跑 head/worker 的每一台节点上加载镜像：**
   - **节点用 Docker 作容器运行时：**
     ```bash
     # 把 dcgm-mndiag.tar.gz 和 k8s/load-image.sh 拷到节点后：
     chmod +x load-image.sh
     ./load-image.sh dcgm-mndiag.tar.gz
     ```
     或：`gunzip -c dcgm-mndiag.tar.gz | docker load`
   - **节点用 containerd 时（多数 K8s 默认）：**
     ```bash
     chmod +x load-image-containerd.sh
     ./load-image-containerd.sh dcgm-mndiag.tar.gz
     ```
     或：`gunzip -c dcgm-mndiag.tar.gz | sudo ctr -n k8s.io images import -`

3. **部署：**（在能 kubectl 的机器上，无需改 YAML）
   ```bash
   cd tools/dcgm_mndiag/k8s
   ./deploy.sh
   ```

若改为**从仓库拉取**：把两个 deployment 里的 `image` 改成仓库地址（如 `your-registry.io/dcgm-mndiag:latest`），并把 `imagePullPolicy` 改为 `IfNotPresent` 或 `Always`。

## 3. 部署（手动时）

若不用一键脚本，可按顺序执行：

```bash
./create-ssh-secret.sh
kubectl apply -f namespace.yaml
kubectl apply -f head-deployment.yaml
kubectl apply -f worker-deployment.yaml
kubectl apply -f services.yaml
```

## 4. 两节点部署（当前为 Pod 网络，无 hostNetwork）

当前 **未使用 hostNetwork**：head 在 l20-gpu-04、worker 在 l20-gpu-05，走 Pod 网络，通过 Service 名 `dcgm-mndiag-worker` 免密 SSH。在 head 里执行 `ssh dcgm-mndiag-worker hostname` / `ssh dcgm-mndiag-worker nvidia-smi` 即可。

跨节点 Pod 互通依赖 Calico 已修复（见 [DEBUG-POD-NETWORK.md](DEBUG-POD-NETWORK.md)：为 calico-node 设置 `IP_AUTODETECTION_METHOD=cidr=10.6.131.0/24`）。若集群未做该修复且跨节点不通，可临时改用 hostNetwork 部署（见 git 历史或 DEBUG 文档）。

## 5. 固定到两台节点（可选）

若希望 head 和 worker 分别落在两台机器上，且集群允许跨节点 Pod 互通，编辑：

- `head-deployment.yaml`：在 `spec.template.spec` 下加 `nodeName: <节点1名>` 或 `nodeSelector`
- `worker-deployment.yaml`：加 `nodeName: <节点2名>` 或 `nodeSelector`

## 6. L20 / 仅测免密与单机命令（默认）

mndiag 仅支持 GB200 NVL / GB300 NVL，**L20 等 GPU 跑不了 mndiag**。默认 `RUN_MNDIAG=false`，Head Pod 只起 sshd + nv-hostengine 并常驻，方便你先验证两 Pod 免密和单机命令。

部署后：

```bash
# 进入 head pod
kubectl exec -it -n dcgm-mndiag deployment/dcgm-mndiag-head -- bash

# 在 head 里测试免密到 worker
ssh dcgm-mndiag-worker hostname
ssh dcgm-mndiag-worker nvidia-smi

# 本机（head）看 GPU
dcgmi discovery -n
nvidia-smi

# 在 worker 上执行命令（免密）
ssh dcgm-mndiag-worker dcgmi discovery -n
```

**重要：从 head Pod 里连 worker 必须用 Service 名，不要用节点 IP。**

- 用 **Service 名**（由 K8s DNS 解析到 worker Pod IP）：
  ```bash
  ssh dcgm-mndiag-worker
  ping dcgm-mndiag-worker
  ```
- 不要用节点 IP（如 10.30.229.238）：Pod 网络里访问的是 Pod IP，用节点 IP 会连到节点主机而不是 worker 容器，且可能不通。
- 若当前镜像没有 `ping`，重建镜像后会有（Dockerfile 已加 iputils-ping）；也可用 `nc -zv dcgm-mndiag-worker 22` 测端口。

**若 `ssh dcgm-mndiag-worker` 仍失败，在 head 里逐条执行排查：**
```bash
# 1) DNS 是否解析
getent hosts dcgm-mndiag-worker

# 2) 22 端口是否通
nc -zv dcgm-mndiag-worker 22

# 3) 本机私钥是否存在
ls -la /root/.ssh/id_rsa

# 4) 详细 SSH 看报错
ssh -vvv -o ConnectTimeout=5 dcgm-mndiag-worker
```
在集群外看 worker 是否在跑、sshd 是否起来：`kubectl get pod -n dcgm-mndiag -o wide`、`kubectl logs -n dcgm-mndiag deployment/dcgm-mndiag-worker`。

确认免密和单机命令都正常后，再考虑在支持的 NVL 环境里把 `RUN_MNDIAG` 改为 `true` 跑完整 mndiag。

## 7. 跑完整 mndiag（仅 NVL 等支持型号）

若集群是 GB200/GB300 NVL，在 `head-deployment.yaml` 里把环境变量改为：

```yaml
- name: RUN_MNDIAG
  value: "true"
```

然后 `kubectl apply -f head-deployment.yaml` 并重建 head Pod。Head 会执行一次 mndiag 后退出。

再次跑：`kubectl delete pod -n dcgm-mndiag -l role=head` 让 head 重建即可。

## 8. 文件说明

| 文件 | 说明 |
|------|------|
| `namespace.yaml` | 命名空间 dcgm-mndiag |
| `ssh-secret.yaml.example` | Secret 示例（一般用 create-ssh-secret.sh 即可） |
| `deploy.sh` | 一键部署（Secret + namespace + head + worker + services） |
| `load-image.sh` | 在节点上加载 tar.gz 到 Docker（Docker 运行时用） |
| `load-image-containerd.sh` | 在节点上加载 tar.gz 到 containerd（containerd 运行时用，多数 K8s） |
| `setup-node-ssh.sh` | 两节点间配置免密 SSH（只在一台执行，输入对方密码一次即双向免密） |
| `sync-image-to-node.sh` | 免密后把镜像 tar 拷到另一节点并 ctr 加载 |
| `create-ssh-secret.sh` | 生成密钥并创建 dcgm-mndiag-ssh Secret |
| `head-deployment.yaml` | Head（默认 RUN_MNDIAG=false 常驻；可改为 true 跑 mndiag） |
| `worker-deployment.yaml` | Worker 节点（sshd + nv-hostengine） |
| `services.yaml` | head/worker Service，供 DNS 与 hostList 解析 |
