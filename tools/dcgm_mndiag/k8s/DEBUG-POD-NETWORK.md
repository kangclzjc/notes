# 不用 hostNetwork 时 Pod 间不通的排查结论（已修复）

## 修复说明（2026-02-14）

**原因**：Calico 在 l20-gpu-05 上自动检测到的是 10.6.130.201（接口 ibs845f0），与 K8s 节点 InternalIP 10.6.131.36 不一致，导致 IPIP 隧道对端不可达。

**修复**：在 calico-node DaemonSet 中增加环境变量，强制 Calico 只使用与节点同网段的 IP：
```bash
kubectl patch daemonset -n kube-system calico-node --type='json' -p='[{"op": "add", "path": "/spec/template/spec/containers/0/env/-", "value": {"name": "IP_AUTODETECTION_METHOD", "value": "cidr=10.6.131.0/24"}}]'
```
滚动更新后，l20-gpu-05 使用 10.6.131.36，跨节点 Pod 间 ping/TCP 已恢复正常。

若你的节点不在 10.6.131.0/24，请将 `cidr=10.6.131.0/24` 改为你的节点 InternalIP 所在网段（如 `cidr=10.6.131.0/24` 或 `interface=eth0` 等，见 [Calico 文档](https://docs.tigera.io/calico/latest/reference/node/configuration#ip-autodetection-methods)）。

---

## 现象（修复前）

- **同节点** Pod 间：ping / TCP 均通（如 10.30.108.204 ↔ 10.30.108.205 在 l20-gpu-04 上）。
- **跨节点** Pod 间：ping 100% 丢包，TCP 连接超时（如 10.30.108.204 @ l20-gpu-04 → 10.30.229.240 @ l20-gpu-05）。

因此不是 SSH 或 22 端口的问题，而是**跨节点 Pod 网络整体不通**。

## 环境摘要

| 项目 | 值 |
|------|-----|
| CNI | Calico |
| Pod CIDR | 10.30.0.0/16（节点 04: 10.30.0.0/24，节点 05: 10.30.1.0/24） |
| IPPool | 10.30.0.0/16，ipipMode: **Always**，natOutgoing: true |
| 节点 | l20-gpu-04: 10.6.131.35，l20-gpu-05: 10.6.131.36 |

## 可能根因（Calico 隧道 / 节点 IP 不一致）

Calico 日志里 l20-gpu-05 上有：

```text
Using autodetected IPv4 address on interface ibs845f0: 10.6.130.201/24
```

即 Calico 在 05 上选中的是 **10.6.130.201**（接口 `ibs845f0`），而 K8s 节点 InternalIP 是 **10.6.131.36**。  
IPIP 隧道若用 10.6.130.201 做对端，而路由/防火墙只放行 10.6.131.x，或 04 到 10.6.130.201 不可达，就会导致跨节点 Pod 流量失败。

## 建议排查步骤（由集群/网络管理员在节点上执行）

### 1. 确认 Calico 在各节点上使用的 IP

在 l20-gpu-04、l20-gpu-05 上执行（或通过 Calico 文档查对应 CRD/配置）：

```bash
# 看 Calico 自动检测到的 IP
kubectl logs -n kube-system -l k8s-app=calico-node --tail=500 | grep -i "autodetected\|Using.*address"
```

确认两节点用于建隧道的 IP 是否与 K8s 的 InternalIP 一致，以及 04 是否能 ping 通 05 上 Calico 用的那个 IP。

### 2. 固定 Calico 使用与 K8s 一致的节点 IP（若不一致）

若希望 Calico 在 l20-gpu-05 上使用 10.6.131.36 而不是 10.6.130.201，可设置 IP 自动检测方法，例如：

- 在 Calico 的 node 配置或 env 中设置 `IP_AUTODETECTION_METHOD=interface=eth0`（或实际连接 10.6.131.36 的接口名），使隧道建立在 10.6.131.36 上；或
- 使用 `IP_AUTODETECTION_METHOD=can-reach=10.6.131.35` 等，让选出的 IP 与节点间互通一致。

（具体配置方式以你当前安装的 Calico 版本文档为准。）

### 3. 检查节点间路由与防火墙

在 l20-gpu-04 上：

```bash
# 到 05 上 Pod 网段的路由
ip route get 10.30.229.240

# 到 05 节点 IP 是否通（含 10.6.131.36 和 10.6.130.201）
ping -c 1 10.6.131.36
ping -c 1 10.6.130.201
```

若 `ip route get` 指向 10.6.130.201，而 04 上 ping 不通 10.6.130.201，则需在底层网络/防火墙上放行 10.6.130.x 与 10.6.131.x 之间的 Calico 隧道流量（IPIP 协议，通常 4 或 94）。

### 4. 可选：尝试 VXLAN 代替 IPIP

若 IPIP 在现网环境下难以打通，可考虑将 Calico IPPool 改为 VXLAN  overlay（或 `ipipMode: CrossSubnet` 等），减少对当前路由/防火墙的依赖。修改前建议在测试环境或非关键集群先试。

## 当前规避方式

在未修复跨节点 Pod 网络前，dcgm-mndiag 使用 **hostNetwork**，让 head/worker 走节点网络与节点间 SSH（与「容器外免密」一致），worker sshd 监听 2222，head 通过 `NODE_WORKER_IP` + 2222 连 worker，可正常使用。

## 复现跨节点不通的快速验证

```bash
# 创建两个 Pod 分属两节点
kubectl run netdebug04 --restart=Never --image=nicolaka/netshoot --overrides='{"spec":{"nodeName":"l20-gpu-04","containers":[{"name":"c","image":"nicolaka/netshoot","command":["sleep","3600"]}]}}'
kubectl run netdebug05 --restart=Never --image=nicolaka/netshoot --overrides='{"spec":{"nodeName":"l20-gpu-05","containers":[{"name":"c","image":"nicolaka/netshoot","command":["sleep","3600"]}]}}'

# 等 Running 后取 IP
kubectl get pod netdebug04 netdebug05 -o wide

# 从 04 的 Pod ping 05 的 Pod（会 100% 丢包）
kubectl exec netdebug04 -- ping -c 2 <netdebug05 的 IP>
```

结论：**不用 hostNetwork 就不行** 的原因是：当前集群**跨节点 Pod 网络（Calico IPIP + 节点 IP/路由）未通**，与 SSH/22 无关；修好跨节点 Pod 连通性后，可去掉 hostNetwork 并改回 Pod 网络 + Service 名访问。
