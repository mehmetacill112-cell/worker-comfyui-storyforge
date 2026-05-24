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

# Build-time symlinks: /comfyui/models/{ipadapter-flux,clip_vision} -> /runpod-volume/models/
#
# Debug pod confirmed (2026-05-24 18:04 UTC):
#   - /comfyui/models/ipadapter-flux DOES NOT EXIST on worker
#   - /runpod-volume/models/ipadapter-flux/ip-adapter.bin EXISTS (5.0 GB)
#   - folder_paths.models_dir = /comfyui/models (ComfyUI default)
#   - Custom node ComfyUI-IPAdapter-Flux registers folder_paths.models_dir + "ipadapter-flux"
#
# Symlink at build time, target resolves at runtime when network volume mounts
# at /runpod-volume (base image yaml + xtts/wav2lip handlers all use this path).
# Also keep extra_model_paths registration as belt+suspenders.
RUN mkdir -p /runpod-volume/models/ipadapter-flux /runpod-volume/models/clip_vision \
 && ln -sfn /runpod-volume/models/ipadapter-flux /comfyui/models/ipadapter-flux \
 && ln -sfn /runpod-volume/models/clip_vision /comfyui/models/clip_vision \
 && cat >> /comfyui/extra_model_paths.yaml <<'YAML_APPEND'

storyforge_ipa_runpodvolume:
  base_path: /runpod-volume
  ipadapter-flux: models/ipadapter-flux/
YAML_APPEND

RUN echo "=== Final symlinks + yaml state ===" \
 && ls -la /comfyui/models/ipadapter-flux /comfyui/models/clip_vision \
 && echo "---" \
 && cat /comfyui/extra_model_paths.yaml

# PR #107 compat patch — ComfyUI v0.14+ removed flipped_img_txt direct access on
# FLUX DoubleStreamBlock. Custom node ComfyUI-IPAdapter-Flux v.latest still uses
# direct .flipped_img_txt access in flux/layers.py:30, causing AttributeError
# during workflow execution (Vertex QA smoke 2026-05-24 18:29 UTC).
# PR #107 fix uses getattr() with default False. Apply here as inline sed/python
# patch until upstream merges (PRs #103/#105/#106/#107/#108 all open).
RUN python3 - <<'PYEOF'
import pathlib

# ─── Patch 1: flux/layers.py — flipped_img_txt getattr (PR #107) ───
p1 = pathlib.Path("/comfyui/custom_nodes/ComfyUI-IPAdapter-Flux/flux/layers.py")
s1 = p1.read_text()
old1 = "self.flipped_img_txt = original_block.flipped_img_txt"
new1 = "self.flipped_img_txt = getattr(original_block, 'flipped_img_txt', False)  # storyforge PR#107 compat"
if old1 not in s1:
    raise SystemExit("PR#107 patch anchor not found in flux/layers.py")
p1.write_text(s1.replace(old1, new1, 1))
print("PR#107 flipped_img_txt compat applied to flux/layers.py")

# ─── Patch 2: utils.py — forward_orig_ipa signature (PR #108) ───
# ComfyUI v0.14+ passes timestep_zero_index + other kwargs that the custom
# node's forward_orig_ipa didn't accept. Add them + **kwargs catch-all.
p2 = pathlib.Path("/comfyui/custom_nodes/ComfyUI-IPAdapter-Flux/utils.py")
s2 = p2.read_text()
old2 = """    y: Tensor,
    guidance: Tensor|None = None,
    control=None,
    transformer_options={},
    attn_mask: Tensor = None,
) -> Tensor:"""
new2 = """    y: Tensor,
    guidance: Tensor|None = None,
    control=None,
    timestep_zero_index=None,  # storyforge PR#108 ComfyUI v0.14+ compat
    transformer_options={},
    attn_mask: Tensor = None,
    **kwargs,  # storyforge PR#108 catch-all for future ComfyUI API changes
) -> Tensor:"""
if old2 not in s2:
    raise SystemExit("PR#108 patch anchor not found in utils.py")
p2.write_text(s2.replace(old2, new2, 1))
print("PR#108 forward_orig_ipa signature patch applied to utils.py")
PYEOF

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
