"""Provision the pinned Windows CI toolchain; private signing data never enters Git."""
import base64
import hashlib
import os
from pathlib import Path
import re
import shutil
import subprocess
import urllib.request
import zipfile

ROOT = Path(__file__).resolve().parents[2]
VERSION = "4.7.2"
BASE = f"https://github.com/godotengine/godot-builds/releases/download/{VERSION}-stable"
DOWNLOADS = {
    f"Godot_v{VERSION}-stable_win64.exe.zip": "731980f9608d61333e5baf54a2ef17210acc7a538446c0cb9969f002aca1e953",
    f"Godot_v{VERSION}-stable_export_templates.tpz": "f298490b8d44d934be425a5a65a51bf15f422428b229a06a6e11d9ffea248011",
}
TAG_PATTERN = r"v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(?:-([A-Za-z0-9]+(?:[.-][A-Za-z0-9]+)*))?"


def sha256(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def download(name, digest, destination):
    print(f"Downloading official {name}", flush=True)
    request = urllib.request.Request(f"{BASE}/{name}", headers={"User-Agent": "VoxelProject-CI"})
    with urllib.request.urlopen(request, timeout=120) as source, destination.open("wb") as target:
        shutil.copyfileobj(source, target, length=1024 * 1024)
    if sha256(destination) != digest:
        raise RuntimeError(f"Official download SHA256 mismatch: {name}")


def main():
    tag = os.environ["BUILD_TAG"]
    if not re.fullmatch(TAG_PATTERN, tag):
        raise ValueError("Expected version tag vMAJOR.MINOR.PATCH[-suffix], e.g. v0.1.1-demo")
    # run_number is unchanged on reruns and increments for each new run of this workflow.
    code = int(os.environ["GITHUB_RUN_NUMBER"]) + 1
    if not 1 < code < 2100000000:
        raise ValueError("Android version code outside the supported range")
    key = os.environ.pop("ANDROID_DEBUG_KEYSTORE_BASE64", "")
    if not key:
        raise RuntimeError("Missing repository Actions secret ANDROID_DEBUG_KEYSTORE_BASE64")
    tool_root = ROOT / ".build/tools"
    tool_root.mkdir(parents=True, exist_ok=True)
    (ROOT / ".build/.gdignore").touch()
    (tool_root / "debug.keystore").write_bytes(base64.b64decode(key, validate=True))
    del key

    downloads = tool_root / "downloads"
    downloads.mkdir(exist_ok=True)
    for name, digest in DOWNLOADS.items():
        download(name, digest, downloads / name)

    editor = tool_root / "godot"
    editor.mkdir(exist_ok=True)
    with zipfile.ZipFile(downloads / f"Godot_v{VERSION}-stable_win64.exe.zip") as archive:
        archive.extractall(editor)
    templates = tool_root / "templates"
    templates.mkdir(exist_ok=True)
    with zipfile.ZipFile(downloads / f"Godot_v{VERSION}-stable_export_templates.tpz") as archive:
        for name in ("windows_debug_x86_64.exe", "windows_release_x86_64.exe", "android_debug.apk", "android_release.apk"):
            with archive.open(f"templates/{name}") as source, (templates / name).open("wb") as target:
                shutil.copyfileobj(source, target)

    # Reuse the local packaging script's directory contract without copying the SDK/JDK.
    java = Path(os.environ["JAVA_HOME"])
    sdk = Path(os.environ["ANDROID_HOME"])
    jdk_parent = tool_root / "jdk17"
    jdk_parent.mkdir(exist_ok=True)
    for destination, source in ((jdk_parent / "ci", java), (tool_root / "android-sdk", sdk)):
        subprocess.run(["cmd", "/c", "mklink", "/J", str(destination), str(source)], check=True)

    presets_path = ROOT / "export_presets.cfg"
    presets = presets_path.read_text(encoding="utf-8")
    presets, count = re.subn(r'^version/code=\d+$', f"version/code={code}", presets, flags=re.M)
    if count != 1:
        raise RuntimeError("Expected exactly one Android version/code option")
    presets, count = re.subn(r'^version/name="[^"]*"$', f'version/name="{tag[1:]}"', presets, flags=re.M)
    if count != 1:
        raise RuntimeError("Expected exactly one Android version/name option")
    presets_path.write_text(presets, encoding="utf-8")

    godot = editor / f"Godot_v{VERSION}-stable_win64_console.exe"
    with open(os.environ["GITHUB_OUTPUT"], "a", encoding="utf-8") as output:
        output.write(f"godot={godot}\nversion_code={code}\n")
    print(f"Prepared Godot {VERSION}, Android {tag[1:]} (code {code})", flush=True)


if __name__ == "__main__":
    main()
