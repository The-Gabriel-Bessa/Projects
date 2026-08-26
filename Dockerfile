FROM runpod/serverless-pytorch:1.24.0-pytorch2.5.0-cuda12.4.0

ENV PYTORCH_CUDA_ALLOC_CONF=expandable_segments:True
ENV HF_HUB_DISABLE_TELEMETRY=1
ENV PIP_NO_CACHE_DIR=1

WORKDIR /app

RUN apt-get update && apt-get install -y --no-install-recommends \
    git build-essential ninja-build libgl1 libglib2.0-0 \
    && rm -rf /var/lib/apt/lists/*

RUN git clone --depth 1 https://github.com/comfyanonymous/ComfyUI.git /app/ComfyUI

RUN pip install --no-cache-dir -r /app/ComfyUI/requirements.txt

RUN git clone --depth 1 https://github.com/visualbruno/ComfyUI-Trellis2.git /app/ComfyUI/custom_nodes/ComfyUI-Trellis2

RUN pip install --no-cache-dir -r /app/ComfyUI/custom_nodes/ComfyUI-Trellis2/requirements.txt || true

RUN find /app/ComfyUI/custom_nodes/ComfyUI-Trellis2/wheels -name "*.whl" -exec pip install --no-cache-dir {} + || true

RUN pip install --no-cache-dir comfy-cli huggingface_hub runpod

RUN python -c " \
from huggingface_hub import snapshot_download; \
import os; \
os.makedirs('/app/ComfyUI/models/Pixal3D-GGUF', exist_ok=True); \
snapshot_download('Aero-Ex/Pixal3D-GGUF', local_dir='/app/ComfyUI/models/Pixal3D-GGUF', \
    allow_patterns=['pipeline.json','decoder/*','*Q4_K_M*']); \
os.makedirs('/app/ComfyUI/models/dinov3', exist_ok=True); \
snapshot_download('Aero-Ex/Dinov3', local_dir='/app/ComfyUI/models/dinov3'); \
"

RUN pip install --no-cache-dir --upgrade "torch==2.7.0" "torchvision==0.22.0" --index-url https://download.pytorch.org/whl/cu124

COPY . /app

EXPOSE 8188
CMD ["python", "-u", "rp_handler.py"]
