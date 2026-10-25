# Distributed LLM inference on your laptop

A fleet of 3 vLLM servers behind llm-d's cache-aware router (Envoy + EPP),
on a 4-node kubeadm cluster in Multipass VMs — one OpenAI-compatible API,
with Prometheus + Grafana.

![architecture](docs/assets/experiment-04/architecture.png)

**Requires:** Apple Silicon Mac, 24GB RAM, ~40GB disk, [Homebrew](https://brew.sh).
Everything else is installed for you; all compute stays inside the VMs.

## Quick setup — one command

```sh
curl -fsSL https://raw.githubusercontent.com/umairkhancis/exp-inference-on-k8s/experiment/04/install.sh | bash
```

~45–60 min on first run. May prompt once for your password (`/etc/hosts`
entry, Multipass install). Safe to rerun — every layer is idempotent.

## Manual setup — step by step

```sh
git clone https://github.com/umairkhancis/exp-inference-on-k8s.git
cd exp-inference-on-k8s

make host-prereqs       # 1. dependencies + Ubuntu image
make up                 # 2. Kubernetes cluster (VMs -> kubeadm -> CNI -> verify)
make llmd-up            # 3. llm-d: gateway + EPP + vLLM fleet + routing proofs
make llmd-monitoring    # 4. Prometheus + Grafana
```

Finer-grained layers (`make instances`, `make llmd-router`, …) are in the Makefile.

## Use it

```sh
curl -s http://inference.local:30080/v1/completions \
  -H 'Content-Type: application/json' \
  -d '{"model": "Qwen/Qwen2.5-0.5B-Instruct", "prompt": "Kubernetes is", "max_tokens": 32}' | jq
```

- Grafana: `http://inference.local:30300` (admin/admin) · Prometheus: `:30090`
- kubectl: `export KUBECONFIG=$(pwd)/kubeconfig/config`
- No hosts entry? Use the master IP the install prints.

## Prove the routing

```sh
make llmd-verify-affinity   # 8 shared-prefix requests -> ONE pod, with cache hits
make llmd-verify-spread     # 12 unrelated requests    -> spread across the fleet
```

## Tear down

```sh
make llmd-down && make down
```
