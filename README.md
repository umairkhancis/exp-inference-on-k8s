# Flat-Rate Inference on K8s

Run a private, OpenAI-compatible LLM inference engine (vLLM) on a
single-node Kubernetes cluster — fully sandboxed inside a Multipass VM on
your own laptop. Zero dollars per token. Zero host contamination.

```
[ Your app / curl on the host ]
            │  http://<vm-ip>:8000/v1   (OpenAI-compatible)
            ▼
[ Multipass VM: <username>-inference-engine ]   ← the security boundary
            │  systemd port-forward 0.0.0.0:8000
            ▼
[ minikube (single-node k8s) ]
            │  Service vllm (NodePort 30800)
            ▼
[ Pod: vLLM CPU engine — Qwen2.5-0.5B-Instruct ]
```

**Why a VM?** Nobody should pipe a random script into `bash` on their host.
Every install step below runs inside an isolated Ubuntu VM. Destroying the
whole experiment is one command: `multipass delete --purge <name>`.

## Quick start (one command)

```bash
curl -sfL https://raw.githubusercontent.com/umairkhancis/exp-inference-on-k8s/main/install.sh | bash
```

~10–20 minutes on first run (image pull + model download). At the end you
get an endpoint like `http://192.168.64.X:8000/v1`.

## Security-explicit path (3 commands)

Prefer to see each boundary before crossing it? Run the steps yourself:

```bash
# 1. Host: install Multipass — the only thing ever installed on your host
./scripts/01-install-multipass.sh

# 2. Host: create the isolated VM (<you>-inference-engine) and enter its shell
./scripts/02-create-instance.sh

# 3. Inside the VM shell: stand up minikube + the vLLM stack
./inference/03-setup-stack.sh
```

## Verification (from your host)

```bash
./verify/curl-check.sh      # chat completion round-trip through the stack
./verify/metrics-check.sh   # vLLM Prometheus /metrics performance numbers
./verify/load-test.sh       # 10 parallel simulated developers, latency + tok/s
```

Point any OpenAI SDK at it by changing one line:

```python
from openai import OpenAI

client = OpenAI(base_url="http://<vm-ip>:8000/v1", api_key="local")
r = client.chat.completions.create(
    model="Qwen/Qwen2.5-0.5B-Instruct",
    messages=[{"role": "user", "content": "Hello from my own infra"}],
)
print(r.choices[0].message.content)
```

## Configuration

| Variable        | Default                     | Used by                  |
|-----------------|-----------------------------|--------------------------|
| `INSTANCE_NAME` | `<username>-inference-engine` | all scripts            |
| `VM_CPUS`       | `4`                         | 02-create-instance.sh    |
| `VM_MEMORY`     | `8G`                        | 02-create-instance.sh    |
| `VM_DISK`       | `40G`                       | 02-create-instance.sh    |
| `MODEL`         | `Qwen/Qwen2.5-0.5B-Instruct`| verify scripts           |
| `DEVELOPERS`    | `10`                        | load-test.sh             |
| `DURATION`      | `60` (seconds)              | load-test.sh             |

The served model is defined in `manifests/vllm.yaml`. Swap the model arg
and the HF cache keeps each download so restarts are instant.

## Notes on the stack

- **CPU inference, on purpose.** Multipass on Apple Silicon cannot pass the
  GPU through to a Linux VM, so the pod runs a multi-arch CPU build of vLLM
  ([`mekayelanik/vllm-cpu`](https://hub.docker.com/r/mekayelanik/vllm-cpu)).
  A 0.5B model keeps it interactive. The same manifest moves to a GPU
  cluster by swapping the image for `vllm/vllm-openai` and adding an
  `nvidia.com/gpu` resource limit.
- **minikube** (docker driver) is the k8s layer — Layer 2.1 of the plan.
  The manifests are vanilla k8s and port directly to EKS/GKE/K3s.
- **Metrics are native.** vLLM exposes Prometheus metrics on the same port
  (`/metrics`): token counters, TTFT, E2E latency, KV-cache usage — the raw
  material for the cost-divergence dashboard in a later phase.

## Measured on this stack (Apple M5 Pro host, 4-CPU/8G VM)

- 10 parallel developers for 60s: **49/49 requests OK**, ~35 tok/s
  sustained, p50 latency 12.2s at full saturation (`max_tokens=64`).
- Single request: ~0.4s time-to-first-token, ~1.5s end-to-end.

## Teardown

```bash
multipass delete --purge $(whoami)-inference-engine
```

Host untouched.
