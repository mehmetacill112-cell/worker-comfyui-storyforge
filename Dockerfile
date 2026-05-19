FROM runpod/worker-comfyui:5.8.5-base

RUN git clone --depth 1 https://github.com/Lightricks/ComfyUI-LTXVideo /comfyui/custom_nodes/ComfyUI-LTXVideo \
 && git clone --depth 1 https://github.com/Kosinkadink/ComfyUI-VideoHelperSuite /comfyui/custom_nodes/ComfyUI-VideoHelperSuite \
 && pip install --no-cache-dir -r /comfyui/custom_nodes/ComfyUI-LTXVideo/requirements.txt \
 && pip install --no-cache-dir -r /comfyui/custom_nodes/ComfyUI-VideoHelperSuite/requirements.txt \
 && echo "=== Trying to import LTXV __init__ ===" \
 && cd /comfyui && python -c "import sys; sys.path.insert(0, '/comfyui'); sys.path.insert(0, '/comfyui/custom_nodes/ComfyUI-LTXVideo'); import importlib.util; spec = importlib.util.spec_from_file_location('ltxv_init', '/comfyui/custom_nodes/ComfyUI-LTXVideo/__init__.py'); mod = importlib.util.module_from_spec(spec); spec.loader.exec_module(mod); print('LTXV NODE_CLASS_MAPPINGS keys:', list(getattr(mod, 'NODE_CLASS_MAPPINGS', {}).keys())[:10])" 2>&1 | tee /tmp/ltxv_import.log; echo "---exit=$?"; tail -50 /tmp/ltxv_import.log || true
