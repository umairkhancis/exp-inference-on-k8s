#!/usr/bin/env bash
# Layer 3 — control plane.
# Runs kubeadm init on the master, then installs the cluster prerequisites
# llm-d needs underneath it: a CNI (flannel) and a default StorageClass
# (local-path). No llm-d components are installed here.

source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

MASTER_IP="$(vm_ip "${MASTER_NAME}")"

if multipass exec "${MASTER_NAME}" -- sudo test -f /etc/kubernetes/admin.conf; then
  log "Control plane already initialized on ${MASTER_NAME} (${MASTER_IP})"
else
  log "Running kubeadm init on ${MASTER_NAME} (${MASTER_IP})"
  multipass exec "${MASTER_NAME}" -- sudo kubeadm init \
    --apiserver-advertise-address "${MASTER_IP}" \
    --pod-network-cidr "${POD_CIDR}" \
    --node-name "${MASTER_NAME}"
fi

master_kubectl() {
  multipass exec "${MASTER_NAME}" -- sudo env KUBECONFIG=/etc/kubernetes/admin.conf kubectl "$@"
}

log "Installing flannel CNI"
master_kubectl apply -f "${FLANNEL_MANIFEST}"

log "Installing local-path-provisioner and marking it the default StorageClass"
master_kubectl apply -f "${LOCAL_PATH_MANIFEST}"
master_kubectl patch storageclass local-path \
  -p '{"metadata":{"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'

log "Control plane ready"
