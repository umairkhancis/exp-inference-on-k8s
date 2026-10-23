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

## Phase 2 — llm-d: distributed inference with cache-aware routing

On top of the phase-1 cluster, one command deploys llm-d's standalone router
(Envoy gateway + EPP endpoint picker) and three vLLM CPU model servers, one
pinned to each worker:

```sh
make llmd-up
```

It follows the [llm-d quickstart](https://llm-d.ai/docs/getting-started/quickstart)
(repo cloned at `release-1.0` into `~/.cache/exp-inference-on-k8s/llm-d`), with
our deltas in `scripts/setup-llm-d/`: router/EPP downsized for small nodes
(`values/cpu-arm64.values.yaml`) and the guide's 64-core x86 CPU recipe patched
to 3× `Qwen/Qwen2.5-0.5B-Instruct` on ARM64 (`manifests/modelserver/`).

| Make target | What it does |
|---|---|
| `llmd-resize-workers` | Workers 4G → 6G RAM, rolling (vLLM CPU needs the headroom) |
| `llmd-repo` | Pinned quickstart clone |
| `llmd-prereqs` | Gateway API Inference Extension CRDs, namespace, HF token secret |
| `llmd-router` | `llm-d-router-standalone` chart: Envoy + EPP with prefix-cache-affinity + token-load scorers |
| `llmd-modelservers` | 3 × vLLM CPU (`vllm/vllm-openai-cpu:v0.31.0`, arm64), one per worker via required anti-affinity |
| `llmd-gateway` | NodePort 30080 → Envoy listener |
| `llmd-verify` | Completion via the gateway + both routing proofs below |
| `llmd-verify-affinity` | Same prompt prefix ⇒ all requests pin to ONE vLLM pod, with prefix-cache hits |
| `llmd-verify-spread` | Distinct prompts ⇒ requests spread across pods (load-based, no false pinning) |
| `llmd-monitoring` | Prometheus + Grafana per the llm-d guide: kube-prometheus-stack (right-sized), EPP ServiceMonitor, decode PodMonitor, llm-d dashboards; Grafana at NodePort 30300 (admin/admin) |
| `llmd-down` | Remove llm-d (cluster stays) |

`make llmd-verify` proves the phase-2 claim end to end from the host: a curl to
`http://<master-ip>:30080/v1/completions` answers 200 through Envoy (ext-proc
header), then 8 requests sharing a ~500-token prefix all land on the same vLLM
pod with prefix-cache hits — the EPP routing by cache affinity, not round-robin:

```
optimized-...-4bqhb (k8s-worker-3) queries+8088 hits+6272
optimized-...-kp4nb (k8s-worker-1) queries+0    hits+0
optimized-...-p7fm8 (k8s-worker-2) queries+0    hits+0
```

Hard-won ARM64/CPU specifics baked into `manifests/modelserver/patch-vllm-arm64.yaml`:
`--enforce-eager` + explicit `--kv-cache-memory-bytes` (skips the warmup pass
whose memory spike fails the KV allocation check on small cgroups), and
`VLLM_ENABLE_V1_MULTIPROCESSING=0` (single process instead of three, saving
~2G of duplicated torch RSS). Do **not** set `TORCHDYNAMO_DISABLE=1` with
vLLM ≥ 0.31 — the CPU engine aborts at startup.

### Sizing (override via env vars)

| | CPUs | RAM | Disk |
|---|---|---|---|
| `k8s-master` | 2 | 3G | 20G |
| `k8s-worker-{1..3}` | 3 | 4G | 30G |

E.g. `WORKER_MEM=6G WORKER_COUNT=2 make up`. All knobs live in
`scripts/setup-k8s-cluster/lib/common.sh`.
