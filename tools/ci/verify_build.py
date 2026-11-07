"""Validate distributables and record the exact source and Android signing identity."""
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import zipfile

ROOT = Path(__file__).resolve().parents[2]
OUTPUT = ROOT / "exports/release"
FILES = ("MoonExcavation-Windows-x64.zip", "MoonExcavation-Android.apk")
# Public certificate fingerprint of the first published demo. The private key is a Secret.
EXPECTED_SIGNER = "56889b57ae32a6ee6e30f814f0df7d599c5db7ccff50692aee26bfef8c8a6544"


def main():
    hashes = []
    for name in FILES:
        path = OUTPUT / name
        if path.stat().st_size < 1024 * 1024:
            raise RuntimeError(f"Unexpectedly small artifact: {name}")
        with zipfile.ZipFile(path) as archive:
            if archive.testzip():
                raise RuntimeError(f"ZIP CRC failed: {name}")
            entries = archive.namelist()
            if name.endswith(".zip"):
                if sorted(entries) != ["MoonExcavation.exe", "README.txt"]:
                    raise RuntimeError("Windows ZIP must contain only the executable and instructions")
            else:
                for required in ("AndroidManifest.xml", "lib/arm64-v8a/libgodot_android.so", "lib/armeabi-v7a/libgodot_android.so", "assets/project.binary"):
                    if required not in entries:
                        raise RuntimeError(f"APK missing {required}")
                if sum(item.startswith("assets/.godot/imported/") and item.endswith(".sample") for item in entries) != 30:
                    raise RuntimeError("APK is missing imported audio samples")
            if any(part in entries for part in ("debug.keystore", ".demo-data/progression.cfg")):
                raise RuntimeError("Unexpected development data in package")
        with path.open("rb") as stream:
            digest = hashlib.file_digest(stream, "sha256").hexdigest()
        hashes.append(f"{digest}  {name}")

    apk = OUTPUT / FILES[1]
    build_tools = Path(os.environ["ANDROID_HOME"]) / "build-tools/35.0.1"
    signer = subprocess.check_output([str(build_tools / "apksigner.bat"), "verify", "--verbose", "--print-certs", str(apk)], text=True)
    match = re.search(r"Signer #1 certificate SHA-256 digest: ([0-9a-f]+)", signer)
    if not match:
        raise RuntimeError("APK signer verification did not return a certificate")
    if match[1] != EXPECTED_SIGNER:
        raise RuntimeError("APK signing identity changed; cannot safely update the existing demo")
    badging = subprocess.check_output([str(build_tools / "aapt.exe"), "dump", "badging", str(apk)], text=True, encoding="utf-8")
    version = os.environ["BUILD_TAG"][1:]
    code = int(os.environ["GITHUB_RUN_NUMBER"]) + 1
    if f"versionCode='{code}'" not in badging or f"versionName='{version}'" not in badging or "name='com.qinmy.moonexcavationdemo'" not in badging:
        raise RuntimeError("APK package or version does not match this build")
    (OUTPUT / "SHA256SUMS.txt").write_text("\n".join(hashes) + "\n", encoding="utf-8")
    metadata = {
        "tag": os.environ["BUILD_TAG"], "version": version, "version_code": code,
        "commit": os.environ["GITHUB_SHA"], "godot": "4.7.2-stable",
        "signer": match[1], "android_build": "debug-signed demo",
        "workflow_run": f"{os.environ['GITHUB_SERVER_URL']}/{os.environ['GITHUB_REPOSITORY']}/actions/runs/{os.environ['GITHUB_RUN_ID']}",
    }
    (OUTPUT / "build-info.json").write_text(json.dumps(metadata, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(metadata, indent=2))
    print("BUILD_VERIFIED: CRC, audio, ABI, Android version, signature and SHA256")


if __name__ == "__main__":
    main()
