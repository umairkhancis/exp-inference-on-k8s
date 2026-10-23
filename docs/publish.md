# Publishing Log

## Post #1 — 2026-10-12

I have been experimenting with vLLM. One my experiment is deploying inference layer on k8s, and you can run it yourself.

Run your own LLM inference on Kubernetes from your own laptop.

It requires three things:

1. An isolated Ubuntu VM using Multipass. Nothing else is installed on your machine.
2. A small Kubernetes cluster inside that VM, using minikube.
3. vLLM serving the Qwen2.5 0.5B model with an API that works like the OpenAI API.

Point any application (OpenAI SDK or cURL script) at it by changing one line in your code. 

Numbers from my MacBook, using CPU only inference in a small VM:

1. 10 users sending requests at the same time for 60 seconds.
2. About 35 tokens per second.
3. Live Prometheus metrics out of the box: latency, time to first token, and token counts.

Try it with one command. The install command sits at the top of the repo README, ready to copy. The repo also has a step by step path if you want to see each step before you run it, plus load test scripts and all the details:

https://github.com/umairkhancis/exp-inference-on-k8s

(The full command is also visible in the attached image. LinkedIn rewrites any link inside post text, so copy it from the README.)

#vLLM #Kubernetes #LLM #SelfHosted #MLOps

## Post #2 — experiment/02

Self-hosted inference can slash AI cost by 10x.

In my last post I showed how to run your own LLM inference layer on Kubernetes from a laptop. 

This experiment answers the next question: what does it actually save?

The key idea is two different cost functions:

1. Frontier APIs charge per token. The bill is variable. Every new automation, every agent, every retry makes it grow.
2. Self-hosted inference costs a flat rate per GPU hour. The bill is fixed. It does not care how many tokens flow through the box.

So I added an observability layer to the stack: Prometheus scrapes the vLLM metrics, and Grafana shows three dashboards.

Checkout Grafana dashboards open `http://inference.local:3000` after spinning up the local stack. 

Installation instructions are in the repository (link is in the comments section).

#vLLM #Kubernetes #LLM #SelfHosted #MLOps #Grafana #TokenEconomics

## Post #3 — experiment/03

Experiment #03: You can chat with a self-hosted LLM right now.

https://successful-deny-shares-replies.trycloudflare.com

No API key, no GPU, no per-token bill.

1. Open the link and sign up.

2. You will be talking to Qwen2.5 0.5B. Expect small-model answers, not GPT-5.

3. Everything you type is served from a local CPU server.

Behind the scenes, vLLM serving the model on a small Kubernetes cluster with the freedom AI stack of Open Web UI.

Experiment #01 showed you can run your own inference layer on Kubernetes from a laptop. 

Experiment #02 showed how having local inference layer can change the AI automation economics compared to per-token. 

You can try this yourself. 

Link to the repository is in the comments section.

#vLLM #Kubernetes #LLM #SelfHosted #MLOps #OpenWebUI

## Post #4 — experiment/04

Experiment #04: Distributed inference on your laptop, the way the big labs route it.

One vLLM server was experiments 1–3. But that's not how LLMs are served at scale — at scale you run a fleet, and the hard problem becomes routing: which replica should answer this request?

Naive load balancing wastes the most valuable thing a model server has: its KV cache. If your request shares a prefix with an earlier one (same system prompt, same conversation), the pod that served it can skip recomputing all those tokens — but only if the router sends you back to that exact pod.

That's what llm-d does, and I ran it on a real Kubernetes cluster on my MacBook:

1. 4 Ubuntu VMs via Multipass: 1 master + 3 workers, bootstrapped with kubeadm. Real cluster, not minikube.

2. llm-d's gateway: an Envoy proxy that asks an Endpoint Picker (EPP) where to send every request.

3. A fleet of 3 vLLM replicas serving Qwen2.5 0.5B, one per worker node.

Then I measured the routing, from outside the cluster:

1. 8 requests sharing a long prompt prefix → all 8 landed on the SAME pod, which reported thousands of prefix-cache hit tokens. No recompute.

2. 12 unrelated requests → spread 4/4/4 across the fleet. No false pinning.

Cache-aware when it should be, load-balanced when it shouldn't.

One command to try it (Apple Silicon, 24GB RAM): ./install.sh — it brings up the cluster, the gateway, the fleet, and Grafana dashboards, then proves the routing claims against your own machine.

Link to the repository is in the comments section.

#llmd #vLLM #Kubernetes #LLM #SelfHosted #MLOps #DistributedInference
