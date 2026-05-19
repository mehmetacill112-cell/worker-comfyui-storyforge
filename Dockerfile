FROM runpod/worker-comfyui:5.8.5-base

RUN git clone --depth 1 https://github.com/Lightricks/ComfyUI-LTXVideo /comfyui/custom_nodes/ComfyUI-LTXVideo \
 && git clone --depth 1 https://github.com/Kosinkadink/ComfyUI-VideoHelperSuite /comfyui/custom_nodes/ComfyUI-VideoHelperSuite \
 && pip install --no-cache-dir -r /comfyui/custom_nodes/ComfyUI-LTXVideo/requirements.txt \
 && pip install --no-cache-dir -r /comfyui/custom_nodes/ComfyUI-VideoHelperSuite/requirements.txt \
 && echo "=== Trying to import LTXV (proper relative-import setup) ===" \
 && cd /comfyui && python -c "import sys, importlib.util; root='/comfyui/custom_nodes/ComfyUI-LTXVideo'; spec=importlib.util.spec_from_file_location('ltxv_pkg', root+'/__init__.py', submodule_search_locations=[root]); mod=importlib.util.module_from_spec(spec); sys.modules['ltxv_pkg']=mod; spec.loader.exec_module(mod); print('LTXV NODE_CLASS_MAPPINGS keys:', list(getattr(mod, 'NODE_CLASS_MAPPINGS', {}).keys())[:15])" 2>&1 | tee /tmp/ltxv_import.log; echo "exit=$?"
