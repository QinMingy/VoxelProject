#!/usr/bin/env python3
"""Publish verified Godot CI artifacts without replacing a public release.

Only the Python standard library is required. Authentication stays in GH_TOKEN;
neither the token nor request headers are written to logs or artifacts.
"""

from __future__ import annotations

import argparse
from dataclasses import dataclass
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import sys
from typing import Any
from urllib.error import HTTPError, URLError
from urllib.parse import quote
from urllib.request import Request, urlopen
import zipfile


TAG_PATTERN = re.compile(
    r"v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)"
    r"(?:-([A-Za-z0-9]+(?:[.-][A-Za-z0-9]+)*))?\Z"
)
SHA_PATTERN = re.compile(r"[0-9a-f]{40}\Z")
PACKAGE_NAMES = (
    "MoonExcavation-Windows-x64.zip",
    "MoonExcavation-Android.apk",
)
ASSET_NAMES = (*PACKAGE_NAMES, "SHA256SUMS.txt", "build-info.json")


class PublishError(Exception):
    """An actionable error that does not contain request headers."""


class GitHubError(PublishError):
    def __init__(self, status: int, message: str):
        self.status = status
        super().__init__(f"GitHub HTTP {status}: {message}")


@dataclass(frozen=True)
class Asset:
    path: Path
    size: int
    sha256: str

    @property
    def name(self) -> str:
        return self.path.name

    @property
    def digest(self) -> str:
        return "sha256:" + self.sha256

    @property
    def content_type(self) -> str:
        if self.name.endswith(".zip"):
            return "application/zip"
        if self.name.endswith(".apk"):
            return "application/vnd.android.package-archive"
        if self.name.endswith(".json"):
            return "application/json"
        return "text/plain; charset=utf-8"


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def validate_archive(path: Path) -> None:
    try:
        with zipfile.ZipFile(path) as archive:
            names = archive.namelist()
            if not names or len(names) != len(set(names)):
                raise PublishError(f"Empty archive or duplicate entries: {path.name}")
            for name in names:
                normalized = name.replace("\\", "/")
                parts = PurePosixPath(normalized).parts
                if normalized.startswith("/") or ".." in parts or (parts and ":" in parts[0]):
                    raise PublishError(f"Unsafe archive path in {path.name}")
                if any(part in {".build", ".demo-data", ".git"} for part in parts):
                    raise PublishError(f"Development-only content in {path.name}")
                if normalized.lower().endswith((".keystore", ".jks", ".p12")):
                    raise PublishError(f"Signing key found in {path.name}")
            required = "MoonExcavation.exe" if path.suffix == ".zip" else "AndroidManifest.xml"
            if required not in names:
                raise PublishError(f"Missing {required} in {path.name}")
            if archive.testzip() is not None:
                raise PublishError(f"ZIP CRC verification failed: {path.name}")
    except (zipfile.BadZipFile, RuntimeError, OSError) as error:
        raise PublishError(f"Cannot verify archive {path.name}: {type(error).__name__}") from None


def validate_artifacts(directory: Path, tag: str, commit: str) -> tuple[list[Asset], dict[str, Any]]:
    directory = directory.resolve(strict=True)
    if not directory.is_dir():
        raise PublishError("Artifact directory is not a directory")
    for name in ASSET_NAMES:
        candidate = directory / name
        if candidate.is_symlink() or not candidate.is_file() or candidate.stat().st_size == 0:
            raise PublishError(f"Missing, empty or symlinked artifact: {name}")
    try:
        info = json.loads((directory / "build-info.json").read_text(encoding="utf-8-sig"))
    except (ValueError, OSError):
        raise PublishError("build-info.json is not valid UTF-8 JSON") from None
    if not isinstance(info, dict):
        raise PublishError("build-info.json must contain an object")
    for field, expected in (("commit", commit), ("tag", tag), ("version", tag[1:])):
        if info.get(field) != expected:
            raise PublishError(f"Build metadata {field} does not match this workflow/tag")
    code = info.get("version_code")
    if isinstance(code, bool) or not isinstance(code, int) or not 1 <= code <= 2_100_000_000:
        raise PublishError("Build metadata version_code must be a valid positive Android version code")
    signer = info.get("signer")
    if not isinstance(signer, (str, dict)) or not signer:
        raise PublishError("Build metadata must identify the Android signer")

    checksums: dict[str, str] = {}
    for line in (directory / "SHA256SUMS.txt").read_text(encoding="utf-8-sig").splitlines():
        if not line.strip():
            continue
        match = re.fullmatch(r"([0-9a-fA-F]{64})[ \t]+\*?([^\r\n]+)", line)
        if not match or match[2] not in PACKAGE_NAMES or match[2] in checksums:
            raise PublishError("SHA256SUMS.txt must list each Windows/Android package exactly once")
        checksums[match[2]] = match[1].lower()
    if set(checksums) != set(PACKAGE_NAMES):
        raise PublishError("SHA256SUMS.txt must contain exactly the Windows ZIP and Android APK")

    assets = [Asset(directory / name, (directory / name).stat().st_size, sha256(directory / name)) for name in ASSET_NAMES]
    for asset in assets:
        if asset.name in checksums:
            if asset.sha256 != checksums[asset.name]:
                raise PublishError(f"Local SHA256 mismatch: {asset.name}")
            validate_archive(asset.path)
    return assets, info


class GitHub:
    def __init__(self, repository: str, token: str):
        self.repository = repository
        self._token = token
        self.api = f"https://api.github.com/repos/{repository}"

    def _sanitize(self, message: str) -> str:
        message = message.replace(self._token, "[redacted]")
        message = re.sub(r"(?:gh[pousr]_[A-Za-z0-9]+|github_pat_[A-Za-z0-9_]+)", "[redacted]", message)
        return " ".join(message.split())[:300]

    def request(self, method: str, endpoint: str, payload: Any = None, asset: Asset | None = None) -> Any:
        url = self.api + endpoint
        headers = {
            "Authorization": f"Bearer {self._token}",
            "Accept": "application/vnd.github+json",
            "X-GitHub-Api-Version": "2022-11-28",
            "User-Agent": "VoxelProject-Tagged-Release",
        }
        stream = None
        try:
            data: Any = None
            if asset is not None:
                # Stream the package, retaining a fixed Content-Length instead of
                # buffering an APK in memory or relying on chunked transfer.
                url = f"https://uploads.github.com/repos/{self.repository}{endpoint}"
                headers["Content-Type"] = asset.content_type
                headers["Content-Length"] = str(asset.size)
                stream = asset.path.open("rb")
                data = stream
            elif payload is not None:
                data = json.dumps(payload, ensure_ascii=False).encode("utf-8")
                headers["Content-Type"] = "application/json; charset=utf-8"
            request = Request(url, data=data, method=method, headers=headers)
            with urlopen(request, timeout=600 if asset else 90) as response:
                body = response.read()
                return json.loads(body) if body else None
        except HTTPError as error:
            try:
                result = json.loads(error.read(64 * 1024))
                message = result.get("message", "Request rejected") if isinstance(result, dict) else "Request rejected"
            except (ValueError, OSError):
                message = "Request rejected"
            raise GitHubError(error.code, self._sanitize(str(message))) from None
        except (URLError, TimeoutError, OSError):
            raise PublishError("GitHub network operation failed; rerun to resume the draft") from None
        finally:
            if stream is not None:
                stream.close()

    def resolve_tag(self, tag: str) -> str:
        ref = self.request("GET", f"/git/ref/tags/{quote(tag, safe='')}")
        obj = ref.get("object", {})
        visited = set()
        for _ in range(16):
            sha = obj.get("sha", "")
            if not SHA_PATTERN.fullmatch(sha) or sha in visited:
                raise PublishError("Remote version tag contains an invalid/cyclic object")
            visited.add(sha)
            if obj.get("type") == "commit":
                return sha
            if obj.get("type") != "tag":
                raise PublishError("Remote version tag does not point to a commit")
            obj = self.request("GET", f"/git/tags/{sha}").get("object", {})
        raise PublishError("Remote version tag exceeds the annotated-tag nesting limit")

    def find_release(self, tag: str) -> dict[str, Any] | None:
        try:
            return self.request("GET", f"/releases/tags/{quote(tag, safe='')}")
        except GitHubError as error:
            if error.status != 404:
                raise
        # Drafts may not be addressable through the by-tag endpoint. Authenticated
        # listing includes them and allows an interrupted upload to continue.
        for page in range(1, 101):
            releases = self.request("GET", f"/releases?per_page=100&page={page}")
            matching = [release for release in releases if release.get("tag_name") == tag]
            if len(matching) > 1:
                raise PublishError("Multiple draft releases use this tag; inspect them before retrying")
            if matching:
                return matching[0]
            if len(releases) < 100:
                return None
        raise PublishError("Release listing exceeded the inspection limit")


def asset_matches(remote: dict[str, Any], local: Asset) -> bool:
    return (
        remote.get("state") == "uploaded"
        and remote.get("size") == local.size
        and (remote.get("digest") or "").lower() == local.digest
    )


def verify_release_assets(release: dict[str, Any], assets: list[Asset]) -> None:
    for asset in assets:
        matching = [item for item in release.get("assets", []) if item.get("name") == asset.name]
        if len(matching) != 1 or not asset_matches(matching[0], asset):
            raise PublishError(f"Remote attachment size/SHA256/state does not match: {asset.name}")


def release_notes(repository: str, tag: str, commit: str, info: dict[str, Any]) -> str:
    return f"""此版本由 GitHub Actions 根据 `{tag}` 自动构建并发布。

- Windows：下载 `MoonExcavation-Windows-x64.zip`，解压后运行 `MoonExcavation.exe`。
- Android：下载 `MoonExcavation-Android.apk` 安装；版本 `{info['version']}`，版本码 `{info['version_code']}`。
- `SHA256SUMS.txt` 可核对两端安装包；`build-info.json` 记录源代码版本及构建信息。

自动校验包含构建来源与标签、压缩包 CRC、SHA256，以及上传后附件的大小和校验值。Android 包由构建步骤校验签名，当前为固定调试签名的试玩 APK。**Android 真机安装、性能、多点触控和声音仍需设备试玩确认。**

源码：[查看对应提交](https://github.com/{repository}/commit/{commit})。
"""


def write_summary(release: dict[str, Any], repository: str, assets: list[Asset]) -> None:
    url = f"https://github.com/{repository}/releases/tag/{quote(release['tag_name'], safe='')}"
    lines = [f"## 发布成功：{release['tag_name']}", "", f"[打开 GitHub Release]({url})", "", "| 下载 | 字节数 | SHA256 |", "| --- | ---: | --- |"]
    for asset in assets:
        download = f"https://github.com/{repository}/releases/download/{quote(release['tag_name'], safe='')}/{asset.name}"
        lines.append(f"| [{asset.name}]({download}) | {asset.size} | `{asset.sha256}` |")
    summary = "\n".join(lines) + "\n"
    print(f"Published and verified: {url}")
    summary_path = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary_path:
        with Path(summary_path).open("a", encoding="utf-8") as output:
            output.write(summary)


def publish(directory: Path) -> None:
    tag = os.environ.get("GITHUB_REF_NAME", "")
    match = TAG_PATTERN.fullmatch(tag)
    if not match:
        raise PublishError("Tag must use vX.Y.Z or vX.Y.Z-suffix with numeric version components")
    commit = os.environ.get("GITHUB_SHA", "").lower()
    if not SHA_PATTERN.fullmatch(commit):
        raise PublishError("GITHUB_SHA must be a complete commit SHA")
    repository = os.environ.get("GITHUB_REPOSITORY", "")
    if not re.fullmatch(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+", repository):
        raise PublishError("GITHUB_REPOSITORY must identify owner/repository")
    token = os.environ.get("GH_TOKEN", "")
    if not token:
        raise PublishError("GH_TOKEN is required")
    assets, info = validate_artifacts(directory, tag, commit)
    github = GitHub(repository, token)
    if github.resolve_tag(tag) != commit:
        raise PublishError("Remote tag no longer points to the exact workflow source commit")
    prerelease = match[4] is not None
    release = github.find_release(tag)
    if release is not None and not release.get("draft"):
        # An exact rerun can succeed without touching a public release. Any
        # changed asset must use a new tag, even when the source is unchanged.
        verify_release_assets(release, assets)
        if bool(release.get("prerelease")) != prerelease:
            raise PublishError("Existing public release has a different prerelease classification")
        write_summary(release, repository, assets)
        return
    if release is not None:
        if release.get("target_commitish") != commit:
            raise PublishError("Existing draft targets a different commit; it will not be replaced")
    else:
        release = github.request("POST", "/releases", {
            "tag_name": tag,
            "target_commitish": commit,
            "name": f"月面采掘 {tag}",
            "body": release_notes(repository, tag, commit, info),
            "draft": True,
            "prerelease": prerelease,
        })
    release_id = release["id"]
    print(f"Verified source; preparing draft release {release_id}")
    for asset in assets:
        matching = [item for item in release.get("assets", []) if item.get("name") == asset.name]
        if len(matching) > 1:
            raise PublishError(f"Duplicate draft attachments: {asset.name}")
        if matching and asset_matches(matching[0], asset):
            print(f"Already verified: {asset.name}")
            continue
        if matching:
            # Only this unpublished draft and exact source commit can reach
            # here. Replace a failed/partial upload before it becomes public.
            github.request("DELETE", f"/releases/assets/{matching[0]['id']}")
        print(f"Uploading {asset.name} ({asset.size} bytes)", flush=True)
        remote = github.request("POST", f"/releases/{release_id}/assets?name={quote(asset.name, safe='')}", asset=asset)
        if not asset_matches(remote, asset):
            raise PublishError(f"Uploaded attachment failed size/SHA256 verification: {asset.name}")
        print(f"Verified: {asset.name}", flush=True)
    release = github.request("GET", f"/releases/{release_id}")
    if not release.get("draft") or release.get("target_commitish") != commit:
        raise PublishError("Release changed during upload; publication stopped")
    verify_release_assets(release, assets)
    if github.resolve_tag(tag) != commit:
        raise PublishError("Version tag changed during upload; publication stopped")
    release = github.request("PATCH", f"/releases/{release_id}", {
        "draft": False,
        "prerelease": prerelease,
        "make_latest": "false" if prerelease else "legacy",
    })
    if release.get("draft") or not release.get("published_at"):
        raise PublishError("GitHub did not confirm publication")
    verify_release_assets(release, assets)
    write_summary(release, repository, assets)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("artifact_directory", type=Path)
    args = parser.parse_args()
    try:
        publish(args.artifact_directory)
    except (PublishError, OSError, ValueError, KeyError, TypeError) as error:
        # Never dump a traceback/request object containing the Authorization
        # header. These errors contain only validated local data/API messages.
        message = str(error)
        token = os.environ.get("GH_TOKEN", "")
        if token:
            message = message.replace(token, "[redacted]")
        print(f"Release publication stopped: {message}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
