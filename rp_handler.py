import os, sys, time, uuid, base64, subprocess, threading
from pathlib import Path
import requests
import runpod

COMFY_DIR = "/app/ComfyUI"
COMFY_PORT = 8188
COMFY_URL = f"http://127.0.0.1:{COMFY_PORT}"
WORKFLOW = "/app/pixal3d_meshonly_q8.json"
INPUT_DIR = os.path.join(COMFY_DIR, "input")
OUTPUT_DIR = "/app/comfy_out"
COMFY_OUT = os.path.join(COMFY_DIR, "output")
EXTRA_ARGS = os.environ.get("COMFY_EXTRA_ARGS", "").split()
_comfy_proc = None
_lock = threading.Lock()


def _ensure_comfy():
    global _comfy_proc
    with _lock:
        try:
            if requests.get(f"{COMFY_URL}/system_stats", timeout=5).status_code == 200:
                return
        except Exception:
            pass
        os.makedirs(INPUT_DIR, exist_ok=True)
        os.makedirs(OUTPUT_DIR, exist_ok=True)
        log = open("/app/comfy.log", "a")
        _comfy_proc = subprocess.Popen(
            [sys.executable, "main.py", "--port", str(COMFY_PORT), *EXTRA_ARGS],
            cwd=COMFY_DIR, stdout=log, stderr=subprocess.STDOUT)
        for _ in range(200):
            time.sleep(3)
            try:
                if requests.get(f"{COMFY_URL}/system_stats", timeout=5).status_code == 200:
                    return
            except Exception:
                pass
        raise RuntimeError("ComfyUI failed to start; see /app/comfy.log")


def _fetch_image(uri, dest):
    if uri.startswith("data:"):
        _, b64 = uri.split(",", 1)
        dest.write_bytes(base64.b64decode(b64))
    elif uri.startswith("http://") or uri.startswith("https://"):
        r = requests.get(uri, timeout=120)
        r.raise_for_status()
        dest.write_bytes(r.content)
    else:
        dest.write_bytes(base64.b64decode(uri))
    return dest


def _build_workflow(image_name, prefix, tmp):
    import json
    with open(WORKFLOW) as f:
        wf = json.load(f)
    for n in wf.get("nodes", []):
        if n.get("id") == 6 and isinstance(n.get("widgets_values"), list):
            n["widgets_values"][0] = image_name
        if n.get("id") == 203 and isinstance(n.get("widgets_values"), list):
            n["widgets_values"][0] = prefix
    with open(tmp, "w") as f:
        json.dump(wf, f)


def _run_comfy(image_path, prefix):
    image_name = Path(image_path).name
    tmp = f"/app/wf_{uuid.uuid4().hex}.json"
    _build_workflow(image_name, prefix, tmp)
    start = time.time()
    out = subprocess.run(
        ["comfy", "run", "--workflow", tmp, "--wait", "--timeout", "1800"],
        capture_output=True, text=True, timeout=1800)
    if out.returncode != 0:
        raise RuntimeError("comfy run failed:\n" + out.stderr[-3000:])
    candidates = []
    for d in (Path(COMFY_OUT), Path(OUTPUT_DIR)):
        for c in d.rglob("*.glb"):
            if c.is_file() and c.stat().st_mtime >= start:
                candidates.append(c)
    glbs = sorted(candidates, key=lambda p: p.stat().st_mtime)
    if not glbs:
        raise RuntimeError("no glb produced; comfy output:\n" + (out.stdout or out.stderr)[-2000:])
    return glbs[-1]


def handler(event):
    inp = (event or {}).get("input", {})
    uri = inp.get("image")
    if not uri:
        return {"error": "missing input.image"}
    prefix = inp.get("filename_prefix", "pixal_clay")
    _ensure_comfy()
    img_path = Path(INPUT_DIR) / f"{uuid.uuid4().hex}.png"
    _fetch_image(uri, img_path)
    glb = _run_comfy(str(img_path), prefix)
    b64 = base64.b64encode(glb.read_bytes()).decode()
    return {"output": {"glb_base64": b64, "glb_path": str(glb), "filename": glb.name}}


runpod.serverless.start({"handler": handler})
