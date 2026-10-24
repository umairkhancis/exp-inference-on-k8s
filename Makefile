# High-level wrapper around the layered setup under scripts/setup-k8s-cluster/.
#
#   make up        — bring up the whole cluster (all layers, in order)
#   make verify    — prove the cluster is healthy from the host
#   make down      — delete the VMs and local kubeconfig
#
# Each layer is also addressable on its own; every target is idempotent.

SHELL := /bin/bash
SCRIPTS := scripts/setup-k8s-cluster
LLMD := scripts/setup-llm-d
export KUBECONFIG := $(CURDIR)/kubeconfig/config

.PHONY: up down status \
	host-prereqs instances node-prereqs control-plane workers kubeconfig verify hostname \
	llmd-up llmd-down llmd-resize-workers llmd-repo llmd-prereqs llmd-router \
	llmd-modelservers llmd-gateway llmd-verify llmd-monitoring \
	llmd-verify-affinity llmd-verify-spread

## Full bring-up: host prereqs → VMs → node runtime → control plane → workers → access → verify
up: host-prereqs instances node-prereqs control-plane workers kubeconfig verify hostname
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

## Layer 7 — map inference.local to the master in /etc/hosts (sudo, best-effort)
hostname:
	$(SCRIPTS)/access/setup-hostname.sh

## Current VM + node state
status:
	multipass list
	-kubectl get nodes -o wide

## Tear everything down (keeps the cached cloud image)
down:
	$(SCRIPTS)/teardown-k8s-cluster.sh

# ---------------- Phase 2: llm-d (Envoy gateway + EPP + vLLM CPU x3) ----------------

## Full llm-d bring-up on the phase-1 cluster
llmd-up: llmd-resize-workers llmd-repo llmd-prereqs llmd-router llmd-modelservers llmd-gateway llmd-verify

## Workers to 6G RAM (rolling) — vLLM CPU needs the headroom
llmd-resize-workers:
	$(LLMD)/host/resize-workers.sh

## Pinned clone of the llm-d quickstart repo (release-1.0)
llmd-repo:
	$(LLMD)/host/fetch-llm-d-repo.sh

## GAIE CRDs + namespace + HF token secret
llmd-prereqs:
	$(LLMD)/cluster/prereqs.sh

## llm-d router standalone chart (Envoy + EPP, cache-aware plugins)
llmd-router:
	$(LLMD)/cluster/install-router.sh

## vLLM CPU model servers, one per worker
llmd-modelservers:
	$(LLMD)/cluster/deploy-modelservers.sh

## NodePort 30080 for host access to the gateway
llmd-gateway:
	$(LLMD)/access/expose-gateway.sh

## Completion via Envoy + both routing proofs
llmd-verify:
	$(LLMD)/access/verify.sh

## Same prompt prefix => same vLLM pod (cache-aware affinity)
llmd-verify-affinity:
	$(LLMD)/access/verify-prefix-affinity.sh

## Distinct prompts => spread across vLLM pods (load-based)
llmd-verify-spread:
	$(LLMD)/access/verify-load-spread.sh

## Prometheus + Grafana per the llm-d guide (Grafana on NodePort 30300)
llmd-monitoring:
	$(LLMD)/cluster/monitoring.sh

## Remove llm-d (keeps cluster, CRDs, clone, worker sizing)
llmd-down:
	$(LLMD)/teardown-llm-d.sh
