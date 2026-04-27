# ClawMem model services for llama.cpp

This directory contains a `compose.yaml` for the **QMD native** ClawMem model stack recommended when you want the ClawMem-recommended models without the heavier non-commercial ZeroEntropy pair:

- embedding: `embeddinggemma-300M-Q8_0.gguf` on port `9088`
- llm: `qmd-query-expansion-1.7B-q4_k_m.gguf` on port `9089`
- reranker: `qwen3-reranker-0.6b-q8_0.gguf` on port `9090`

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
curl -fsS http://127.0.0.1:9088/v1/models
curl -fsS http://127.0.0.1:9089/v1/models
curl -fsS http://127.0.0.1:9090/v1/models
```

## Hermes / ClawMem env on the hermes-office side

Point the Hermes container at this GPU host with environment like:

```env
CLAWMEM_EMBED_URL=http://<gpu-host>:9088
CLAWMEM_LLM_URL=http://<gpu-host>:9089
CLAWMEM_RERANK_URL=http://<gpu-host>:9090
CLAWMEM_NO_LOCAL_MODELS=true
CLAWMEM_SERVE_MODE=external
CLAWMEM_PROFILE=balanced
```

## Notes

- This compose file uses the official `ghcr.io/ggml-org/llama.cpp:server-cuda` image.
- It assumes NVIDIA Container Toolkit is already working on the GPU server.
- For `clawmem-embed`, set **both** `--batch-size 2048` and `--ubatch-size 2048`. Without `--ubatch-size`, llama.cpp may still report a physical batch size of `512`, and `clawmem embed` can fail on larger fragments even though the logical batch size looks large enough.
- The LLM and reranker examples intentionally stay at `--batch-size 512`; raise them only after measuring real need and GPU headroom.
- If another service already occupies `9089` (for example Qwen3.5), either stop that service and let this compose own `9089`, or change the host-side port mapping here and set `CLAWMEM_LLM_URL` accordingly on the Hermes side.
- If you later switch embedding model families, re-run `clawmem embed --force` on the Hermes side.
- The published ports are intentionally plain HTTP with no auth. Only expose them on a trusted private network, VPN, or behind your own authenticated reverse proxy / firewall.
