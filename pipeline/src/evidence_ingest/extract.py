from __future__ import annotations

import io
import re
import struct
import zlib
import zipfile
from html.parser import HTMLParser
from pathlib import Path
from xml.etree import ElementTree

from .contracts import Detection, Extraction

MAX_ARCHIVE_UNCOMPRESSED_BYTES = 200 * 1024 * 1024
MAX_SECTION_BYTES = 50 * 1024 * 1024


class _VisibleHTML(HTMLParser):
    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self.parts: list[str] = []
        self.hidden_depth = 0

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        if tag in {"script", "style", "noscript", "svg"}:
            self.hidden_depth += 1
        elif tag in {"p", "div", "br", "li", "tr", "h1", "h2", "h3", "h4", "td", "th"}:
            self.parts.append("\n")

    def handle_endtag(self, tag: str) -> None:
        if tag in {"script", "style", "noscript", "svg"} and self.hidden_depth:
            self.hidden_depth -= 1
        elif tag in {"p", "div", "li", "tr", "h1", "h2", "h3", "h4"}:
            self.parts.append("\n")

    def handle_data(self, data: str) -> None:
        if not self.hidden_depth:
            self.parts.append(data)


def _decode_text(data: bytes) -> tuple[str, str]:
    for encoding in ("utf-8-sig", "cp949", "utf-16"):
        try:
            return data.decode(encoding), encoding
        except UnicodeDecodeError:
            continue
    return data.decode("utf-8", errors="replace"), "utf-8-replace"


def _extract_html(data: bytes) -> Extraction:
    text, encoding = _decode_text(data)
    parser = _VisibleHTML()
    parser.feed(text)
    visible = "".join(parser.parts)
    return Extraction("extracted", visible, "html.parser", 1, int(bool(visible.strip())), {"encoding": encoding})


def _natural_section_key(name: str) -> tuple[int, str]:
    match = re.search(r"section(\d+)", name, re.IGNORECASE)
    return (int(match.group(1)) if match else 10**9, name)


def _extract_hwpx(data: bytes) -> Extraction:
    texts: list[str] = []
    warnings: list[str] = []
    with zipfile.ZipFile(io.BytesIO(data)) as archive:
        if sum(item.file_size for item in archive.infolist()) > MAX_ARCHIVE_UNCOMPRESSED_BYTES:
            return Extraction("invalid", "", "hwpx-xml", warnings=("archive-uncompressed-limit-exceeded",))
        names = sorted(
            (name for name in archive.namelist() if re.match(r"^Contents/section\d+\.xml$", name, re.IGNORECASE)),
            key=_natural_section_key,
        )
        for name in names:
            try:
                info = archive.getinfo(name)
                if info.file_size > MAX_SECTION_BYTES:
                    warnings.append(f"section-size-limit:{name}")
                    texts.append("")
                    continue
                root = ElementTree.fromstring(archive.read(name))
                section_parts = [node.text or "" for node in root.iter() if node.tag.rsplit("}", 1)[-1] == "t"]
                texts.append("\n".join(section_parts))
            except ElementTree.ParseError as error:
                warnings.append(f"xml-parse-error:{name}:{error}")
                texts.append("")
    with_text = sum(bool(text.strip()) for text in texts)
    status = "extracted" if with_text else "empty"
    return Extraction(status, "\n\n".join(texts), "hwpx-xml", len(texts), with_text, {}, tuple(warnings))


def _hwp_records(data: bytes, compressed: bool) -> str:
    if compressed:
        decompressor = zlib.decompressobj(-15)
        data = decompressor.decompress(data, MAX_SECTION_BYTES + 1)
        if len(data) > MAX_SECTION_BYTES or decompressor.unconsumed_tail:
            raise ValueError("section-uncompressed-limit-exceeded")
    offset = 0
    parts: list[str] = []
    while offset + 4 <= len(data):
        header = struct.unpack_from("<I", data, offset)[0]
        offset += 4
        tag_id = header & 0x3FF
        size = (header >> 20) & 0xFFF
        if size == 0xFFF:
            if offset + 4 > len(data):
                break
            size = struct.unpack_from("<I", data, offset)[0]
            offset += 4
        payload = data[offset : offset + size]
        offset += size
        if tag_id == 67:
            decoded = payload.decode("utf-16le", errors="replace")
            decoded = "".join(char if ord(char) >= 32 else "\n" if char in "\r\n" else " " for char in decoded)
            parts.append(decoded)
    return "\n".join(parts)


def _extract_hwp(path: Path) -> Extraction:
    try:
        import olefile  # type: ignore
    except ImportError:
        return Extraction("parser_unavailable", "", "hwp-ole", warnings=("missing-dependency:olefile",))

    if not olefile.isOleFile(str(path)):
        return Extraction("invalid", "", "hwp-ole", warnings=("not-ole-container",))
    with olefile.OleFileIO(str(path), raise_defects=olefile.DEFECT_INCORRECT) as ole:
        if not ole.exists("FileHeader"):
            return Extraction("invalid", "", "hwp-ole", warnings=("missing-stream:FileHeader",))
        header = ole.openstream("FileHeader").read()
        if not header.startswith(b"HWP Document File"):
            return Extraction("invalid", "", "hwp-ole", warnings=("invalid-hwp-signature",))
        flags = struct.unpack_from("<I", header, 36)[0] if len(header) >= 40 else 0
        compressed = bool(flags & 0x01)
        encrypted = bool(flags & 0x02)
        distribution = bool(flags & 0x04)
        if encrypted or distribution:
            return Extraction(
                "protected",
                "",
                "hwp-ole",
                metadata={"compressed": compressed, "encrypted": encrypted, "distribution": distribution},
                warnings=("hwp-protected:no-bypass-attempted",),
            )
        sections = sorted(
            ("/".join(parts) for parts in ole.listdir() if len(parts) == 2 and parts[0] == "BodyText" and parts[1].startswith("Section")),
            key=_natural_section_key,
        )
        texts: list[str] = []
        warnings: list[str] = []
        for section in sections:
            try:
                texts.append(_hwp_records(ole.openstream(section).read(), compressed))
            except (OSError, ValueError, zlib.error, struct.error) as error:
                warnings.append(f"section-error:{section}:{error}")
                texts.append("")
        with_text = sum(bool(text.strip()) for text in texts)
        return Extraction(
            "extracted" if with_text else "empty",
            "\n\n".join(texts),
            "hwp-ole-records",
            len(sections),
            with_text,
            {"compressed": compressed, "encrypted": False, "distribution": False},
            tuple(warnings),
        )


def _extract_pdf(path: Path) -> Extraction:
    try:
        from pypdf import PdfReader  # type: ignore
    except ImportError:
        return Extraction("parser_unavailable", "", "pypdf", warnings=("missing-dependency:pypdf",))
    try:
        reader = PdfReader(str(path), strict=True)
        if reader.is_encrypted:
            try:
                unlocked = reader.decrypt("")
            except Exception:
                unlocked = 0
            if not unlocked:
                return Extraction("protected", "", "pypdf", len(reader.pages), 0, warnings=("pdf-encrypted:no-bypass-attempted",))
        pages: list[str] = []
        warnings: list[str] = []
        for index, page in enumerate(reader.pages, 1):
            try:
                pages.append(page.extract_text(extraction_mode="layout") or "")
            except Exception as error:
                warnings.append(f"page-error:{index}:{type(error).__name__}")
                pages.append("")
        with_text = sum(bool(text.strip()) for text in pages)
        status = "extracted" if with_text else "needs_ocr"
        return Extraction(status, "\n\n".join(pages), "pypdf-layout", len(pages), with_text, {}, tuple(warnings))
    except Exception as error:
        return Extraction("invalid", "", "pypdf", warnings=(f"pdf-error:{type(error).__name__}",))


def extract_document(path: Path, data: bytes, detection: Detection) -> Extraction:
    if detection.protection_status == "protected":
        return Extraction("protected", "", "classifier", warnings=("drm-detected:no-bypass-attempted",))
    if detection.container_format == "pdf":
        return _extract_pdf(path)
    if detection.container_format == "hwpx":
        return _extract_hwpx(data)
    if detection.container_format == "hwp_ole":
        return _extract_hwp(path)
    if detection.container_format == "html":
        return _extract_html(data)
    if detection.container_format in {"text", "csv"}:
        text, encoding = _decode_text(data)
        return Extraction("extracted", text, "text-decoder", 1, int(bool(text.strip())), {"encoding": encoding})
    return Extraction("unsupported", "", "none", warnings=(f"unsupported:{detection.container_format}",))
