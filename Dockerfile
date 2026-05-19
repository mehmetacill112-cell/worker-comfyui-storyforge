FROM runpod/worker-comfyui:5.8.5-base

RUN comfy-node-install comfyui-ltxvideo comfyui-videohelpersuite
