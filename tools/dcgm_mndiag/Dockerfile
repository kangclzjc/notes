# Dockerfile for running NVIDIA DCGM Multi-Node Diagnostics (mndiag)
# Requires DCGM 4.3.0+, OpenMPI, CUDA toolkit, sshd, and supports GB200 NVL / GB300 NVL clusters.
# See README.md for usage and prerequisites.
#
# Build with custom versions (optional):
#   docker build -t dcgm-mndiag .   # default: DCGM 4.5.1, CUDA 13.1
#   docker build --build-arg DCGM_VERSION=4.4.2-1-ubuntu22.04 --build-arg CUDA_TOOLKIT_VERSION=12-6 -t dcgm-mndiag .
#   docker build --build-arg CUDA_UBUNTU_REPO=ubuntu2404 -t dcgm-mndiag .   # if cuda-toolkit-13-1 needs ubuntu2404

# DCGM base image tag. See https://hub.docker.com/r/nvidia/dcgm/tags (4.5.1 暂无官方镜像，用 4.4.2)
ARG DCGM_VERSION=4.4.2-1-ubuntu22.04
FROM nvidia/dcgm:${DCGM_VERSION}

# CUDA toolkit package version (apt package suffix: 11-8, 12-2, 12-6, 13-1, etc.)
ARG CUDA_TOOLKIT_VERSION=12-6

# Ubuntu repo for CUDA keyring (ubuntu2204 or ubuntu2404; 13.x may need ubuntu2404)
ARG CUDA_UBUNTU_REPO=ubuntu2204

# OpenMPI: required by mndiag for mnubergemm (multi-node ubergemm) stress test.
# openssh-client: SSH client for head node to launch remote tasks.
# openssh-server (sshd): SSH server so this image can run on worker nodes and accept SSH from head node.
# CUDA toolkit: required for mnubergemm and GPU compute on each node.
# See: https://docs.nvidia.com/datacenter/dcgm/latest/user-guide/dcgm-multinode-diagnostics.html
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    wget \
    && wget -q https://developer.download.nvidia.com/compute/cuda/repos/${CUDA_UBUNTU_REPO}/x86_64/cuda-keyring_1.1-1_all.deb \
    && dpkg -i cuda-keyring_1.1-1_all.deb \
    && rm cuda-keyring_1.1-1_all.deb \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
    openmpi-bin \
    openssh-client \
    openssh-server \
    iputils-ping \
    cuda-toolkit-${CUDA_TOOLKIT_VERSION} \
    && rm -rf /var/lib/apt/lists/*

# Ensure sshd can run (privilege separation dir)
RUN mkdir -p /run/sshd

# CUDA runtime for mnubergemm (path is set by cuda-toolkit-* package)
ENV PATH=/usr/local/cuda/bin:${PATH} \
    LD_LIBRARY_PATH=/usr/local/cuda/lib64:${LD_LIBRARY_PATH}

# Point nv-hostengine to mpirun for mndiag orchestration.
# Set at runtime if mpirun is in a different path on the host.
ENV DCGM_MNDIAG_MPIRUN_PATH=/usr/bin/mpirun

# Default: run dcgmi so users can pass "mndiag --hostList ..." as args.
# Example: docker run ... dcgm-mndiag mndiag --hostList "node1;node2" -j
ENTRYPOINT ["dcgmi"]
CMD ["--help"]
