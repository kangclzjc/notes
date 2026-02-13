# DCGM Multi-Node Diagnostics (mndiag)

基于 NVIDIA DCGM 的多节点诊断（mndiag），支持两节点部署并配置免密 SSH。

## 镜像构建（本地 + K8s 用）

**一键构建并可选导入 Kind/Minikube 或导出 tar：**
```bash
cd tools/dcgm_mndiag
chmod +x build-local.sh
./build-local.sh              # 仅构建，镜像名 dcgm-mndiag:latest（K8s 已按此名使用本地镜像）
./build-local.sh --kind       # 构建后导入当前 Kind 集群
./build-local.sh --minikube   # 构建后导入 Minikube
./build-local.sh --save       # 构建后另存为 dcgm-mndiag.tar.gz，拷到其他节点后 docker load
./build-local.sh --save /tmp  # 保存到指定目录
```

K8s 的 YAML 已配置为使用本地镜像（`image: dcgm-mndiag:latest`、`imagePullPolicy: Never`），无需改 YAML。各 GPU 节点上有该镜像后执行 `k8s/deploy.sh` 即可。

## 部署方式

| 方式 | 说明 | 文档 |
|------|------|------|
| **K8s** | 两 Pod（head + worker），固定到两台 GPU 节点，Secret 存 SSH 密钥 | [k8s/README.md](k8s/README.md) |
| **Docker 同机** | 同一台主机上两个容器，docker-compose 网络 + 共享 ssh_keys | [docker/README.md](docker/README.md) |
| **Docker 两机** | 节点1 跑 head，节点2 跑 worker，主机端口映射 + 免密 SSH | [docker/README.md](docker/README.md) |

## 免密 SSH

mndiag 要求**所有参与节点**之间能免密 SSH（同一用户，本方案用 root）：

- 用**同一对** SSH 密钥（无密码）
- **Head** 持有私钥；**Head 和 Worker** 的 `authorized_keys` 里都放同一公钥（head 自连也需要）
- K8s：用 Secret 存密钥，由脚本或示例生成；Docker：`docker/scripts/setup-ssh-keys.sh` 生成 `ssh_keys/`

## 目录结构

```
dcgm_mndiag/
├── Dockerfile
├── build-local.sh      # 构建镜像 + 可选 --kind/--minikube/--save
├── README.md           # 本文件
├── k8s/                # K8s 部署
│   ├── namespace.yaml
│   ├── ssh-secret.yaml.example
│   ├── create-ssh-secret.sh
│   ├── head-deployment.yaml
│   ├── worker-deployment.yaml
│   ├── services.yaml
│   └── README.md
└── docker/             # Docker 部署
    ├── docker-compose.yml
    ├── run-two-nodes.sh
    ├── scripts/setup-ssh-keys.sh
    ├── .gitignore
    └── README.md
```
