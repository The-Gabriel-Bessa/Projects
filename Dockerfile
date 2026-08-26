FROM nvidia/cuda:12.8.0-cudnn-devel-ubuntu24.04

ENV DEBIAN_FRONTEND=noninteractive
ENV PYTORCH_CUDA_ALLOC_CONF=expandable_segments:True
ENV HF_HUB_DISABLE_TELEMETRY=1
ENV PIP_NO_CACHE_DIR=1
ENV PIP_BREAK_SYSTEM_PACKAGES=1

RUN apt-get update && apt-get install -y --no-install-recommends \
    python3 python3-venv python3-pip python3-dev git build-essential \
    libgl1 libglib2.0-0 ninja-build wget && \
    rm -rf /var/lib/apt/lists/*

RUN ln -sf /usr/bin/python3 /usr/local/bin/python && \
    python3 -m pip install --upgrade pip setuptools

WORKDIR /app

RUN python3 -m pip install --no-cache-dir --upgrade \
    "torch==2.7.0" --index-url https://download.pytorch.org/whl/cu128

RUN git clone --depth 1 https://github.com/comfyanonymous/ComfyUI.git /app/ComfyUI

RUN python3 -m pip install --no-cache-dir -r /app/ComfyUI/requirements.txt

RUN git clone --depth 1 https://github.com/visualbruno/ComfyUI-Trellis2.git /app/ComfyUI/custom_nodes/ComfyUI-Trellis2

RUN python3 -m pip install --no-cache-dir -r /app/ComfyUI/custom_nodes/ComfyUI-Trellis2/requirements.txt || true

RUN find /app/ComfyUI/custom_nodes/ComfyUI-Trellis2/wheels/Linux/Torch270 -name "*.whl" \
    -exec python3 -m pip install --no-cache-dir {} + || true

RUN python3 -m pip install --no-cache-dir comfy-cli huggingface_hub runpod

RUN python3 -c " \
from huggingface_hub import snapshot_download; \
import os; \
os.makedirs('/app/ComfyUI/models/Pixal3D-GGUF', exist_ok=True); \
snapshot_download('Aero-Ex/Pixal3D-GGUF', local_dir='/app/ComfyUI/models/Pixal3D-GGUF', \
    allow_patterns=['pipeline.json','decoder/*','*Q4_K_M*']); \
os.makedirs('/app/ComfyUI/models/dinov3', exist_ok=True); \
snapshot_download('Aero-Ex/Dinov3', local_dir='/app/ComfyUI/models/dinov3'); \
"

COPY . /app

EXPOSE 8188
CMD ["python", "-u", "rp_handler.py"]
