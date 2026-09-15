from __future__ import annotations

import json
import ipaddress
import socket
import urllib.parse
import urllib.request
from pathlib import Path

from .hashing import canonical_json_bytes, sha256_bytes
from .pipeline import process_file
from .projection import build_projection, write_outputs

MAX_DOWNLOAD_BYTES = 100 * 1024 * 1024


def _validate_url(url: str, allowed_hosts: set[str]) -> None:
    parsed = urllib.parse.urlparse(url)
    if parsed.scheme != "https" or not parsed.hostname:
        raise ValueError(f"Only explicit HTTPS targets are allowed: {url}")
    if parsed.hostname.lower() not in allowed_hosts:
        raise ValueError(f"Host is not allow-listed: {parsed.hostname}")
    try:
        addresses = {item[4][0] for item in socket.getaddrinfo(parsed.hostname, 443, type=socket.SOCK_STREAM)}
    except socket.gaierror as error:
        raise ValueError(f"DNS resolution failed for {parsed.hostname}") from error
    for address in addresses:
        parsed_address = ipaddress.ip_address(address)
        if any(
            (
                parsed_address.is_private,
                parsed_address.is_loopback,
                parsed_address.is_link_local,
                parsed_address.is_reserved,
                parsed_address.is_multicast,
                parsed_address.is_unspecified,
            )
        ):
            raise ValueError(f"Private or loopback destination is forbidden: {address}")


def _extension(content_type: str, url: str) -> str:
    suffix = Path(urllib.parse.urlparse(url).path).suffix.lower()
    if suffix in {".pdf", ".hwp", ".hwpx", ".html", ".htm", ".csv", ".txt", ".md"}:
        return suffix
    if "html" in content_type:
        return ".html"
    if "pdf" in content_type:
        return ".pdf"
    return ".bin"


def _download(url: str, allowed_hosts: set[str], user_agent: str, timeout: int) -> tuple[bytes, str, str]:
    _validate_url(url, allowed_hosts)
    request = urllib.request.Request(url, headers={"User-Agent": user_agent, "Accept": "*/*"})
    with urllib.request.urlopen(request, timeout=timeout) as response:
        final_url = response.geturl()
        _validate_url(final_url, allowed_hosts)
        content_type = response.headers.get_content_type()
        content_length = response.headers.get("Content-Length")
        if content_length and int(content_length) > MAX_DOWNLOAD_BYTES:
            raise ValueError(f"Download exceeds {MAX_DOWNLOAD_BYTES} bytes")
        data = response.read(MAX_DOWNLOAD_BYTES + 1)
        if len(data) > MAX_DOWNLOAD_BYTES:
            raise ValueError(f"Download exceeds {MAX_DOWNLOAD_BYTES} bytes")
        return data, final_url, content_type


def collect_profile(profile_path: Path, output_root: Path, *, timeout: int = 45) -> dict:
    profile = json.loads(profile_path.read_text(encoding="utf-8"))
    institution_id = profile["institution_id"]
    allowed_hosts = {host.lower() for host in profile["allowed_hosts"]}
    user_agent = profile.get("user_agent", "EvidenceLedgerCollector/1.0 (+public-record-integrity)")
    projections: list[dict] = []
    failures: list[dict] = []

    for target in sorted(profile["targets"], key=lambda item: item["source_id"]):
        source_id = target["source_id"]
        if not target.get("enabled", True):
            continue
        try:
            data, final_url, content_type = _download(target["url"], allowed_hosts, user_agent, timeout)
            suffix = _extension(content_type, final_url)
            raw_dir = output_root / institution_id / source_id / "raw"
            raw_dir.mkdir(parents=True, exist_ok=True)
            source_path = raw_dir / f"source{suffix}"
            source_path.write_bytes(data)
            result, normalized_text = process_file(
                source_path,
                institution_id=institution_id,
                source_id=source_id,
                expected_terms=tuple(target.get("expected_terms", [])),
            )
            document_root = output_root / institution_id / source_id
            write_outputs(result, normalized_text, document_root)
            projection = build_projection(result, normalized_text)
            projections.append(
                {
                    "requested_url": target["url"],
                    "final_url": final_url,
                    "projection": projection,
                }
            )
        except Exception as error:
            failures.append({"source_id": source_id, "error_type": type(error).__name__, "message": str(error)})

    index = {
        "runtime_contract": "collection-index/1.0.0",
        "institution_id": institution_id,
        "documents": projections,
        "failures": failures,
    }
    output_root.mkdir(parents=True, exist_ok=True)
    index_path = output_root / institution_id / "collection-index.json"
    index_path.parent.mkdir(parents=True, exist_ok=True)
    index_path.write_bytes(canonical_json_bytes(index) + b"\n")
    return index


def write_public_snapshot(index: dict, archive_root: Path, snapshot_date: str) -> Path:
    snapshot = {
        "snapshot_contract": "public-collection-snapshot/1.0.0",
        "snapshot_date": snapshot_date,
        "institution_id": index["institution_id"],
        "documents": index["documents"],
        "failures": [
            {"source_id": failure["source_id"], "error_type": failure["error_type"]}
            for failure in index["failures"]
        ],
    }
    snapshot["snapshot_sha256"] = sha256_bytes(canonical_json_bytes(snapshot))
    destination = archive_root / index["institution_id"] / snapshot_date / "collection-index.json"
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_bytes(canonical_json_bytes(snapshot) + b"\n")
    return destination
