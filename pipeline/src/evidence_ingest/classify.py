from __future__ import annotations

import io
import zipfile
from pathlib import Path

from .contracts import Detection

OLE_MAGIC = bytes.fromhex("D0CF11E0A1B11AE1")
PDF_MAGIC = b"%PDF-"
ZIP_MAGIC = b"PK\x03\x04"

DRM_MARKERS = {
    "DRMONE": (b"DRMONE", "DRMONE".encode("utf-16le")),
    "FASOO": (b"FASOO", b"FASOO DRM", "FASOO".encode("utf-16le")),
}


def _marker_scan(data: bytes) -> tuple[str | None, tuple[str, ...]]:
    upper = data.upper()
    for vendor, markers in DRM_MARKERS.items():
        for marker in markers:
            if marker.upper() in upper:
                return vendor, (f"marker:{vendor}",)
    return None, ()


def _zip_kind(data: bytes) -> tuple[str, str, float, tuple[str, ...]]:
    try:
        with zipfile.ZipFile(io.BytesIO(data)) as archive:
            names = {name.replace("\\", "/") for name in archive.namelist()}
            mimetype = ""
            if "mimetype" in names:
                mimetype = archive.read("mimetype").decode("ascii", errors="ignore").strip()
            has_hwpx_sections = any(name.startswith("Contents/section") and name.endswith(".xml") for name in names)
            if "hwp" in mimetype.lower() or has_hwpx_sections:
                return "hwpx", "application/hwp+zip", 1.0, ("zip:hwpx-structure",)
            return "zip", "application/zip", 0.95, ("magic:zip",)
    except zipfile.BadZipFile:
        return "unknown", "application/octet-stream", 0.2, ("invalid:zip",)


def detect_document(path: Path, data: bytes) -> Detection:
    suffix = path.suffix.lower()
    if data.startswith(PDF_MAGIC):
        return Detection("pdf", "application/pdf", "clear", None, 1.0, ("magic:pdf",))
    if data.startswith(ZIP_MAGIC):
        kind, media, confidence, basis = _zip_kind(data)
        return Detection(kind, media, "clear", None, confidence, basis)
    if data.startswith(OLE_MAGIC):
        if suffix == ".hwp":
            return Detection("hwp_ole", "application/x-hwp", "unknown", None, 0.9, ("magic:ole", "extension:hwp"))
        return Detection("ole", "application/x-ole-storage", "unknown", None, 0.8, ("magic:ole",))

    # DRM wrappers place their own header before the wrapped document. Scan only
    # that header region after excluding known clear container signatures; this
    # avoids treating a normal document that merely mentions a vendor as DRM.
    drm_vendor, drm_basis = _marker_scan(data[: 64 * 1024])
    if drm_vendor:
        return Detection(
            container_format="protected_wrapper",
            media_type="application/octet-stream",
            protection_status="protected",
            drm_vendor=drm_vendor,
            confidence=1.0,
            basis=drm_basis,
        )
    if suffix in {".html", ".htm"}:
        return Detection("html", "text/html", "clear", None, 0.8, ("extension:html",))
    if suffix == ".csv":
        return Detection("csv", "text/csv", "clear", None, 0.8, ("extension:csv",))
    if suffix in {".txt", ".md"}:
        return Detection("text", "text/plain", "clear", None, 0.75, (f"extension:{suffix[1:]}",))
    return Detection("unknown", "application/octet-stream", "unknown", None, 0.1, ("no-known-signature",))
