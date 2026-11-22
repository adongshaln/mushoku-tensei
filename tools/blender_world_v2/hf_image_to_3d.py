#!/usr/bin/env python3
"""Run the three public image-to-3D jobs in order, with bounded provider fallback."""

import argparse
import json
import os
from pathlib import Path
import re
import shutil
import struct
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]
WORLD = ROOT / "assets/3d/world_v2"
ASSETS = ("hero_migurd_village", "hero_rikarisu_town", "kit_demon_cliff_a")
SPACES = (
    "tencent/Hunyuan3D-2",
    "tencent/Hunyuan3D-2mini-Turbo",
    "tencent/Hunyuan3D-2.1",
    "JeffreyXiang/TRELLIS",
    "trellis-community/TRELLIS",
    "microsoft/TRELLIS.2",
)
FILE_COMPONENTS = {"File", "Model3D", "Litmodel3d", "Downloadbutton"}


def read_token():
    if token := os.getenv("HF_TOKEN", "").strip():
        return token
    env_file = ROOT / ".env"
    if env_file.is_file():
        for line in env_file.read_text(encoding="utf-8-sig").splitlines():
            name, separator, value = line.strip().removeprefix("export ").partition("=")
            if separator and name.strip() == "HF_TOKEN":
                value = value.strip()
                if value.startswith(("'", '"')):
                    end = value.find(value[0], 1)
                    return value[1:end] if end != -1 else ""
                return value.split("#", 1)[0].strip()
    return ""


def glb_info(path):
    with path.open("rb") as stream:
        header = stream.read(20)
        if len(header) != 20:
            raise ValueError("incomplete GLB header")
        tag, version, size, json_size, chunk_type = struct.unpack("<4sIII4s", header)
        if (tag, version, size, chunk_type) != (b"glTF", 2, path.stat().st_size, b"JSON"):
            raise ValueError("invalid or incomplete GLB 2.0")
        if not 0 < json_size <= min(size - 20, 64 * 1024**2):
            raise ValueError("invalid GLB metadata length")
        doc = json.loads(stream.read(json_size))
    if not doc.get("meshes") or any("uri" in b for b in doc.get("buffers", [])):
        raise ValueError("GLB has no meshes or depends on an external buffer")
    return doc


def texture_rank(doc):
    images, textures = doc.get("images", []), doc.get("textures", [])
    if not images or any("bufferView" not in image and
                         not str(image.get("uri", "")).startswith("data:") for image in images):
        return 0
    if not textures:
        return 0
    materials = doc.get("materials", [])
    albedo = any("baseColorTexture" in mat.get("pbrMetallicRoughness", {}) for mat in materials)
    return (1 + any("normalTexture" in mat for mat in materials)) if albedo else 0


def local_files(value):
    if isinstance(value, (Path, str)):
        p = Path(value)
        if p.suffix.lower() == ".glb":
            yield p
    elif isinstance(value, (list, tuple)):
        for item in value:
            yield from local_files(item)
    elif isinstance(value, dict) and isinstance(value.get("path"), str):
        yield from local_files(value["path"])


def generation_endpoint(endpoints):
    candidates = []
    for name, schema in endpoints.items():
        label = name.lower()
        if not any(tag in label for tag in ("generate", "generation", "image_to_3d")):
            continue
        chained = name == "/image_to_3d" and "/extract_glb" in endpoints
        if "shape_generation" in label or not (chained or any(
            item["component"] in FILE_COMPONENTS for item in schema["returns"]
        )):
            continue
        params = schema["parameters"]
        for image in (p for p in params if p["component"] == "Image"):
            key = image["parameter_name"]
            if key.startswith("mv_"):
                continue
            if any(not p["parameter_has_default"] and p["parameter_name"] != key for p in params):
                continue
            score = 3 * ("glb" in label) + 3 * ("texture" in label) + 3 * ("all" in label)
            candidates.append((score, name, key, params))
    if not candidates:
        raise ValueError("no compatible textured image-to-GLB endpoint")
    return max(candidates, key=lambda option: (option[0], option[2] == "image"))[1:]


def call(client, endpoint, timeout, **kwargs):
    job = client.submit(api_name=endpoint, **kwargs)
    try:
        result = job.result(timeout=timeout)
    except TimeoutError:
        job.cancel()
        raise
    # Generator endpoints can emit a preview before returning the final asset.
    return (result, job.outputs())


def generate(space, concept, output, timeout, token):
    from gradio_client import Client, handle_file

    with tempfile.TemporaryDirectory(prefix="hero-gradio-") as temporary:
        client = Client(space, token=token or False, verbose=False, max_workers=2,
                        httpx_kwargs={"timeout": 20.0}, download_files=temporary,
                        analytics_enabled=False)
        endpoints = client.view_api(print_info=False, return_format="dict")["named_endpoints"]
        endpoint, image_parameter, params = generation_endpoint(endpoints)
        image = concept
        if "/start_session" in endpoints and not endpoints["/start_session"]["parameters"]:
            call(client, "/start_session", 20)
        preprocess = endpoints.get("/preprocess_image", {}).get("parameters", [])
        if len(preprocess) == 1 and preprocess[0]["component"] == "Image":
            prepared, _ = call(client, "/preprocess_image", 45,
                               **{preprocess[0]["parameter_name"]: handle_file(str(concept))})
            image = Path(prepared)
        values = {"seed": 418, "randomize_seed": False, "check_box_rembg": True,
                  "export_texture": True, "file_type": "glb"}
        options = {p["parameter_name"]: values[p["parameter_name"]] for p in params
                   if p["parameter_name"] in values}
        options[image_parameter] = handle_file(str(image))
        print(f"{space} {endpoint}", flush=True)
        result = call(client, endpoint, timeout, **options)
        if endpoint == "/image_to_3d" and "/extract_glb" in endpoints:
            export = endpoints["/extract_glb"]["parameters"]
            if any(not p["parameter_has_default"] for p in export):
                raise ValueError("the stateful GLB export signature changed")
            result = call(client, "/extract_glb", timeout)
        ranked = []
        for candidate in set(local_files(result)):
            try:
                rank = texture_rank(glb_info(candidate))
                if rank:
                    ranked.append((rank, candidate))
            except (OSError, ValueError):
                continue
        if not ranked:
            raise ValueError("the endpoint returned no self-contained GLB with an albedo texture")
        rank, downloaded = max(ranked)
        pending = output.with_suffix(".glb.part")
        try:
            shutil.copyfile(downloaded, pending)
            glb_info(pending)
            pending.replace(output)
        finally:
            pending.unlink(missing_ok=True)
        print(f"Downloaded {output.name} ({output.stat().st_size:,} bytes, normal map: {rank > 1})", flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("assets", nargs="*", metavar="ASSET", help="default: all three concepts")
    parser.add_argument("--timeout", type=float, default=185, help="seconds per generation queue/job")
    parser.add_argument("--worker", choices=SPACES, help=argparse.SUPPRESS)
    args = parser.parse_args()
    assets = args.assets or ASSETS
    if any(asset not in ASSETS for asset in assets) or args.timeout <= 0:
        parser.error("unknown asset name or invalid timeout")
    token = read_token()
    directory = WORLD / "raw_heroes"
    directory.mkdir(parents=True, exist_ok=True)
    if args.worker:
        asset, = assets
        try:
            generate(args.worker, WORLD / "concepts" / f"{asset}.png",
                     directory / f"{asset}_raw.glb", args.timeout, token)
            return 0
        except Exception as error:
            detail = str(error).replace(token, "[redacted]") if token else str(error)
            detail = re.sub(r"hf_[A-Za-z0-9_-]+", "[redacted]", detail)
            print(f"{type(error).__name__}: {' '.join(detail.split())[:550]}", flush=True)
            return 1

    print("HF_TOKEN authentication" if token else "Anonymous public Space access", flush=True)
    unavailable = {}
    failed = []
    for asset in assets:
        output = directory / f"{asset}_raw.glb"
        if output.is_file():
            try:
                if texture_rank(glb_info(output)):
                    print(f"{asset}: existing textured asset verified", flush=True)
                    continue
            except (OSError, ValueError):
                pass
        if not (WORLD / "concepts" / f"{asset}.png").is_file():
            print(f"{asset}: missing concept PNG", flush=True)
            failed.append(asset)
            continue
        for space in SPACES:
            if space in unavailable:
                print(f"{asset} / {space}: skipped after previous failure: {unavailable[space]}", flush=True)
                continue
            try:
                result = subprocess.run([sys.executable, __file__, "--worker", space,
                                         "--timeout", str(args.timeout), asset],
                                        capture_output=True, text=True, timeout=args.timeout + 100)
            except subprocess.TimeoutExpired:
                print(f"{asset} / {space}: exceeded the total attempt time", flush=True)
                continue
            message = result.stdout.strip()
            print(f"{asset} / {space}: {message or 'worker exited without a result'}", flush=True)
            if not result.returncode:
                break
            if any(label in message.lower() for label in (
                "invalid state", "could not fetch api info", "no compatible textured",
                "quota exceeded", "gpu quota", "quota limit", "time limit exceeded",
                "not enough gpu", "rate limit", "exceeded your zerogpu", "texgen_worker",
                "larger than the maximum allowed",
            )):
                unavailable[space] = message
        else:
            failed.append(asset)
    if failed:
        print("Pending:", ", ".join(failed), flush=True)
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
