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
