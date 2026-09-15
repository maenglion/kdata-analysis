from __future__ import annotations

from pathlib import Path

from .classify import detect_document
from .confidence import calculate_extraction_confidence
from .contracts import PARSER_VERSION, RUNTIME_CONTRACT_VERSION, PipelineResult
from .extract import extract_document
from .hashing import sha256_bytes
from .normalize import normalize_text


def process_file(
    path: Path,
    *,
    institution_id: str,
    source_id: str,
    expected_terms: tuple[str, ...] = (),
) -> tuple[PipelineResult, str]:
    data = path.read_bytes()
    source_sha256 = sha256_bytes(data)
    detection = detect_document(path, data)
    extraction = extract_document(path, data, detection)
    normalized_text = normalize_text(extraction.text)
    confidence, factors, matched = calculate_extraction_confidence(
        detection,
        extraction,
        normalized_text,
        expected_terms,
    )
    normalized_hash = sha256_bytes(normalized_text.encode("utf-8")) if normalized_text else None
    result = PipelineResult(
        runtime_contract=RUNTIME_CONTRACT_VERSION,
        parser_version=PARSER_VERSION,
        institution_id=institution_id,
        source_id=source_id,
        source_filename=path.name,
        source_sha256=source_sha256,
        source_bytes=len(data),
        detection=detection,
        extraction=extraction,
        extraction_confidence=confidence,
        confidence_factors=factors,
        normalized_text_sha256=normalized_hash,
        normalized_character_count=len(normalized_text),
        expected_terms=expected_terms,
        matched_terms=matched,
    )
    return result, normalized_text
