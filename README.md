# exp-inference-on-k8s — experiment 04

Distributed LLM inference with [llm-d](https://llm-d.ai) on a real kubeadm
Kubernetes cluster, where the nodes are Multipass VMs on a Mac (ARM64).

## Phase 1 — cluster setup

One command brings up a 4-node cluster (1 master + 3 workers) with everything
llm-d needs underneath it (CNI, default StorageClass, host tooling), but no
llm-d components yet:

```sh
make up           # or: scripts/setup-k8s-cluster/setup-k8s-cluster.sh
```

When it finishes:

```sh
export KUBECONFIG=$(pwd)/kubeconfig/config
kubectl get nodes
```

Tear it all down (keeps the cached cloud image):

```sh
make down
```

### Layers

The setup lives under `scripts/setup-k8s-cluster/`, split into independently
rerunnable, idempotent layers — a failed run can simply be retried. The
Makefile exposes each layer; `make up` chains them in order.

| Make target | Script | What it does |
|---|---|---|
| `host-prereqs` | `host/prereqs.sh` | Host tools (kubectl, helm, helmfile, yq) + hash-verified Ubuntu 24.04 ARM64 cloud image |
| `instances` | `host/create-instances.sh` | Multipass VMs, launched from `file://` image¹ |
| `node-prereqs` | `node/provision-all.sh` | containerd + kubeadm/kubelet/kubectl on every node, in parallel (`node/k8s-node-setup.sh` runs inside each VM) |
| `control-plane` | `cluster/init-control-plane.sh` | `kubeadm init`, flannel CNI, local-path default StorageClass |
| `workers` | `cluster/join-workers.sh` | Joins the 3 workers |
| `kubeconfig` | `access/fetch-kubeconfig.sh` | Admin kubeconfig → `kubeconfig/config`, reachable from the host |
| `verify` | `access/verify.sh` | Nodes Ready, system pods up, nginx scheduling smoke test |
| `status` | — | `multipass list` + `kubectl get nodes` |
| `down` | `teardown-k8s-cluster.sh` | Delete VMs + local kubeconfig |

¹ `multipassd`'s internal downloader truncates image downloads on this host,
so the image is fetched with `curl`, verified against Canonical's SHA256SUMS
(re-downloading from scratch when the `release` alias has moved on), and
launched via `file://`.

### Sizing (override via env vars)

| | CPUs | RAM | Disk |
|---|---|---|---|
| `k8s-master` | 2 | 3G | 20G |
| `k8s-worker-{1..3}` | 3 | 4G | 30G |

E.g. `WORKER_MEM=6G WORKER_COUNT=2 make up`. All knobs live in
`scripts/setup-k8s-cluster/lib/common.sh`.
