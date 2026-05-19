FROM runpod/worker-comfyui:5.8.5-base

# VideoHelperSuite provides VHS_VideoCombine, which writes mp4s under node_output["gifs"].
# LTXVideo plugin is kept in case future workflows want LTXVTiledVAEDecode etc.;
# core ComfyUI already ships LTXVImgToVideo / LTXVConditioning / LTXVScheduler.
RUN git clone --depth 1 https://github.com/Lightricks/ComfyUI-LTXVideo /comfyui/custom_nodes/ComfyUI-LTXVideo \
 && git clone --depth 1 https://github.com/Kosinkadink/ComfyUI-VideoHelperSuite /comfyui/custom_nodes/ComfyUI-VideoHelperSuite \
 && pip install --no-cache-dir -r /comfyui/custom_nodes/ComfyUI-LTXVideo/requirements.txt \
 && pip install --no-cache-dir -r /comfyui/custom_nodes/ComfyUI-VideoHelperSuite/requirements.txt

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
