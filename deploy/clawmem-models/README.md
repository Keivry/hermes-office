# ClawMem model services for llama.cpp

This directory contains a `compose.yaml` for the **QMD native** ClawMem model stack recommended when you want the ClawMem-recommended models without the heavier non-commercial ZeroEntropy pair:

- embedding: `embeddinggemma-300M-Q8_0.gguf` on port `8088`
- llm: `qmd-query-expansion-1.7B-q4_k_m.gguf` on port `8089`
- reranker: `qwen3-reranker-0.6b-q8_0.gguf` on port `8090`

## Download the model files

Create a `models/` directory next to the compose file and download these exact filenames:

```bash
mkdir -p models
cd models
wget https://huggingface.co/ggml-org/embeddinggemma-300M-GGUF/resolve/main/embeddinggemma-300M-Q8_0.gguf
wget https://huggingface.co/tobil/qmd-query-expansion-1.7B-gguf/resolve/main/qmd-query-expansion-1.7B-q4_k_m.gguf
wget https://huggingface.co/ggml-org/Qwen3-Reranker-0.6B-Q8_0-GGUF/resolve/main/qwen3-reranker-0.6b-q8_0.gguf
```

## Start

```bash
docker compose up -d
```

Run that command from inside `deploy/clawmem-models/`.

## Verify

Run these from the GPU host (or another machine that can reach it):

```bash
curl http://127.0.0.1:8088/health
curl http://127.0.0.1:8089/health
curl http://127.0.0.1:8090/health
```

## Hermes / ClawMem env on the hermes-office side

Point the Hermes container at this GPU host with environment like:

```env
CLAWMEM_EMBED_URL=http://<gpu-host>:8088
CLAWMEM_LLM_URL=http://<gpu-host>:8089
CLAWMEM_RERANK_URL=http://<gpu-host>:8090
CLAWMEM_NO_LOCAL_MODELS=true
CLAWMEM_PROFILE=balanced
```

## Notes

- This compose file uses the official `ghcr.io/ggml-org/llama.cpp:server-cuda` image.
- It assumes NVIDIA Container Toolkit is already working on the GPU server.
- If your existing qwen3.5 service already occupies `8089`, either stop it and let this compose own `8089`, or change the host-side port mapping here and set `CLAWMEM_LLM_URL` accordingly on the Hermes side.
- If you later switch embedding model families, re-run `clawmem embed --force` on the Hermes side.
- The published ports are intentionally plain HTTP with no auth. Only expose them on a trusted private network, VPN, or behind your own authenticated reverse proxy / firewall.
