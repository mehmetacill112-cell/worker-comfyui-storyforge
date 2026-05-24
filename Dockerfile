FROM runpod/worker-comfyui:5.8.5-base

# VideoHelperSuite provides VHS_VideoCombine, which writes mp4s under node_output["gifs"].
# LTXVideo plugin is kept in case future workflows want LTXVTiledVAEDecode etc.;
# core ComfyUI already ships LTXVImgToVideo / LTXVConditioning / LTXVScheduler.
RUN git clone --depth 1 https://github.com/Lightricks/ComfyUI-LTXVideo /comfyui/custom_nodes/ComfyUI-LTXVideo \
 && git clone --depth 1 https://github.com/Kosinkadink/ComfyUI-VideoHelperSuite /comfyui/custom_nodes/ComfyUI-VideoHelperSuite \
 && git clone --depth 1 https://github.com/Shakker-Labs/ComfyUI-IPAdapter-Flux /comfyui/custom_nodes/ComfyUI-IPAdapter-Flux \
 && pip install --no-cache-dir -r /comfyui/custom_nodes/ComfyUI-LTXVideo/requirements.txt \
 && pip install --no-cache-dir -r /comfyui/custom_nodes/ComfyUI-VideoHelperSuite/requirements.txt \
 && pip install --no-cache-dir -r /comfyui/custom_nodes/ComfyUI-IPAdapter-Flux/requirements.txt

# Build-time symlinks for IP-Adapter + CLIP-vision model dirs.
# ComfyUI custom node looks at /comfyui/models/ipadapter-flux + /comfyui/models/clip_vision
# but storyforge install_ipadapter.py downloads to /workspace/models/ (network volume).
# Dangling at build, resolve at runtime when volume mounts. More reliable
# than pre_start.sh (base image start.sh may not invoke it consistently).
RUN ln -sfn /workspace/models/ipadapter-flux /comfyui/models/ipadapter-flux \
 && ln -sfn /workspace/models/clip_vision /comfyui/models/clip_vision \
 && echo "=== symlinks created at build ===" \
 && ls -la /comfyui/models/ipadapter-flux /comfyui/models/clip_vision || true

# Patch worker-comfyui handler.py to alias node_output["gifs"] → node_output["images"]
# so VHS_VideoCombine mp4 outputs surface in the response. Upstream PR #133 covers
# the same fix; this is an idempotent in-place edit until that lands.
RUN python3 - <<'PY'
p = '/handler.py'
src = open(p).read()
needle = 'for node_id, node_output in outputs.items():'
patch = (
    needle
    + '\n            if "gifs" in node_output and "images" not in node_output:'
    + '\n                node_output["images"] = node_output["gifs"]'
)
if patch in src:
    print('handler.py already patched')
else:
    new = src.replace(needle, patch, 1)
    assert new != src, 'patch needle not found — handler.py layout changed'
    open(p, 'w').write(new)
    print('handler.py patched: gifs aliased to images')
PY

# pre_start.sh is called by /start.sh before ComfyUI launches.
# Downloads lh_pixar_3d_style LoRA to the network volume if missing.
# Set CIVITAI_TOKEN env var in RunPod endpoint settings if download fails.
RUN printf '#!/usr/bin/env bash\n\
LORA_DIR="/workspace/models/loras"\n\
LORA_FILE="${LORA_DIR}/lh_pixar_3d_style.safetensors"\n\
CIVITAI_URL="https://civitai.com/api/download/models/2591917"\n\
if [ ! -f "${LORA_FILE}" ]; then\n\
    echo "[pre_start] Downloading lh_pixar_3d_style LoRA..."\n\
    mkdir -p "${LORA_DIR}"\n\
    if [ -n "${CIVITAI_TOKEN}" ]; then\n\
        wget -q --header="Authorization: Bearer ${CIVITAI_TOKEN}" "${CIVITAI_URL}" -O "${LORA_FILE}" || true\n\
    else\n\
        wget -q "${CIVITAI_URL}" -O "${LORA_FILE}" || true\n\
    fi\n\
    SZ=$(stat -c%%s "${LORA_FILE}" 2>/dev/null || echo 0)\n\
    if [ "${SZ}" -lt 1048576 ]; then\n\
        echo "[pre_start] WARNING: LoRA too small (${SZ}B). Set CIVITAI_TOKEN env var."\n\
        rm -f "${LORA_FILE}"\n\
    else\n\
        echo "[pre_start] LoRA downloaded OK (${SZ}B)"\n\
    fi\n\
else\n\
    echo "[pre_start] lh_pixar_3d_style.safetensors present, skipping."\n\
fi\n\
\n\
# IP-Adapter + CLIP-vision dir registration for ComfyUI custom node\n\
# (ComfyUI looks at /comfyui/models/ipadapter-flux + /comfyui/models/clip_vision\n\
# but storyforge install_ipadapter.py downloads to /workspace/models/...)\n\
mkdir -p /workspace/models/ipadapter-flux /workspace/models/clip_vision\n\
for DIR in ipadapter-flux clip_vision; do\n\
  TARGET=/comfyui/models/${DIR}\n\
  if [ ! -L "${TARGET}" ]; then\n\
    rm -rf "${TARGET}" 2>/dev/null\n\
    ln -sfn /workspace/models/${DIR} "${TARGET}"\n\
    echo "[pre_start] linked ${TARGET} -> /workspace/models/${DIR}"\n\
  fi\n\
done\n' > /pre_start.sh && chmod +x /pre_start.sh
