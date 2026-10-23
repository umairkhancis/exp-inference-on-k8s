# High-level wrapper around the layered setup under scripts/setup-k8s-cluster/.
#
#   make up        — bring up the whole cluster (all layers, in order)
#   make verify    — prove the cluster is healthy from the host
#   make down      — delete the VMs and local kubeconfig
#
# Each layer is also addressable on its own; every target is idempotent.

SHELL := /bin/bash
SCRIPTS := scripts/setup-k8s-cluster
export KUBECONFIG := $(CURDIR)/kubeconfig/config

.PHONY: up down status \
	host-prereqs instances node-prereqs control-plane workers kubeconfig verify

## Full bring-up: host prereqs → VMs → node runtime → control plane → workers → access → verify
up: host-prereqs instances node-prereqs control-plane workers kubeconfig verify
	@echo
	@echo "Cluster is ready. Use it with:"
	@echo "  export KUBECONFIG=$(KUBECONFIG)"
	@echo "  kubectl get nodes"

## Layer 0 — host tools + hash-verified Ubuntu cloud image
host-prereqs:
	$(SCRIPTS)/host/prereqs.sh

## Layer 1 — multipass VMs (1 master + N workers) from the file:// image
instances:
	$(SCRIPTS)/host/create-instances.sh

## Layer 2 — containerd + kubeadm/kubelet/kubectl on every node
node-prereqs:
	$(SCRIPTS)/node/provision-all.sh

## Layer 3 — kubeadm init + flannel CNI + default StorageClass
control-plane:
	$(SCRIPTS)/cluster/init-control-plane.sh

## Layer 4 — join the workers
workers:
	$(SCRIPTS)/cluster/join-workers.sh

## Layer 5 — admin kubeconfig onto the host
kubeconfig:
	$(SCRIPTS)/access/fetch-kubeconfig.sh

## Layer 6 — nodes Ready, system pods up, scheduling smoke test
verify:
	$(SCRIPTS)/access/verify.sh

## Current VM + node state
status:
	multipass list
	-kubectl get nodes -o wide

## Tear everything down (keeps the cached cloud image)
down:
	$(SCRIPTS)/teardown-k8s-cluster.sh
