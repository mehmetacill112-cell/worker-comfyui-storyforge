FROM runpod/worker-comfyui:5.8.5-base

RUN git clone --depth 1 https://github.com/Lightricks/ComfyUI-LTXVideo /comfyui/custom_nodes/ComfyUI-LTXVideo \
 && git clone --depth 1 https://github.com/Kosinkadink/ComfyUI-VideoHelperSuite /comfyui/custom_nodes/ComfyUI-VideoHelperSuite \
 && pip install --no-cache-dir -r /comfyui/custom_nodes/ComfyUI-LTXVideo/requirements.txt \
 && pip install --no-cache-dir -r /comfyui/custom_nodes/ComfyUI-VideoHelperSuite/requirements.txt \
 && ls -la /comfyui/custom_nodes/ComfyUI-LTXVideo/ | head -15 \
 && ls -la /comfyui/custom_nodes/ComfyUI-VideoHelperSuite/ | head -10
