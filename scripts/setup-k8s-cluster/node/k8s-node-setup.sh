#!/usr/bin/env bash
# Runs INSIDE each VM (as root) — installs the container runtime and the
# kubeadm/kubelet/kubectl packages. Idempotent.

set -euo pipefail
K8S_VERSION="${1:?usage: k8s-node-setup.sh <k8s-minor, e.g. v1.34>}"
export DEBIAN_FRONTEND=noninteractive

echo ">>> [$(hostname)] disabling swap"
swapoff -a || true
sed -i '/\sswap\s/ s/^#*/#/' /etc/fstab || true

echo ">>> [$(hostname)] kernel modules + sysctls"
cat >/etc/modules-load.d/k8s.conf <<EOF
overlay
br_netfilter
EOF
modprobe overlay
modprobe br_netfilter
cat >/etc/sysctl.d/99-kubernetes.conf <<EOF
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF
sysctl --system >/dev/null

echo ">>> [$(hostname)] installing containerd"
apt-get update -q
apt-get install -y -q containerd apt-transport-https ca-certificates curl gpg

mkdir -p /etc/containerd
containerd config default >/etc/containerd/config.toml
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
sed -i 's#sandbox_image = ".*"#sandbox_image = "registry.k8s.io/pause:3.10"#' /etc/containerd/config.toml
systemctl enable containerd
systemctl restart containerd

if ! command -v kubeadm >/dev/null; then
  echo ">>> [$(hostname)] installing kubeadm/kubelet/kubectl (${K8S_VERSION})"
  mkdir -p /etc/apt/keyrings
  curl -fsSL "https://pkgs.k8s.io/core:/stable:/${K8S_VERSION}/deb/Release.key" \
    | gpg --dearmor --yes -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
  echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/${K8S_VERSION}/deb/ /" \
    >/etc/apt/sources.list.d/kubernetes.list
  apt-get update -q
  apt-get install -y -q kubelet kubeadm kubectl
  apt-mark hold kubelet kubeadm kubectl
else
  echo ">>> [$(hostname)] kubeadm already installed, skipping package setup"
fi
systemctl enable kubelet

echo ">>> [$(hostname)] node prerequisites done"
