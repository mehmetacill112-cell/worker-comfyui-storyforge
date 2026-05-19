FROM runpod/worker-comfyui:5.8.5-base

RUN comfy-node-install comfyui-ltxvideo comfyui-videohelpersuite \
 && pip install --no-cache-dir kornia sentencepiece \
 && echo "=== custom_nodes dir contents ===" \
 && ls -la /comfyui/custom_nodes/ \
 && echo "=== LTXV dir ===" \
 && (ls -la /comfyui/custom_nodes/ComfyUI-LTXVideo/ 2>&1 | head -20 || echo "MISSING") \
 && echo "=== VHS dir ===" \
 && (ls -la /comfyui/custom_nodes/ComfyUI-VideoHelperSuite/ 2>&1 | head -10 || echo "MISSING") \
 && echo "=== alt path /workspace ===" \
 && (ls -la /workspace/ 2>&1 | head -5 || echo "no /workspace at build time") \
 && echo "=== COMFYUI_PATH env ===" \
 && env | grep -i comfy || true
