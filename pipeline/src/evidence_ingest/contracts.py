from __future__ import annotations

from dataclasses import asdict, dataclass, field
from typing import Any

RUNTIME_CONTRACT_VERSION = "evidence-ingest-runtime/1.0.0"
PUBLISH_CONTRACT_VERSION = "evidence-publish-document/1.0.0"
PARSER_VERSION = "0.1.0"


@dataclass(frozen=True)
class Detection:
    container_format: str
    media_type: str
    protection_status: str
    drm_vendor: str | None
    confidence: float
    basis: tuple[str, ...] = ()


@dataclass(frozen=True)
class Extraction:
    status: str
    text: str
    parser_name: str
    unit_total: int = 0
    unit_with_text: int = 0
    metadata: dict[str, Any] = field(default_factory=dict)
    warnings: tuple[str, ...] = ()


@dataclass(frozen=True)
class ConfidenceFactor:
    code: str
    value: float
    weight: float
    basis: str


@dataclass(frozen=True)
class PipelineResult:
    runtime_contract: str
    parser_version: str
    institution_id: str
    source_id: str
    source_filename: str
    source_sha256: str
    source_bytes: int
    detection: Detection
    extraction: Extraction
    extraction_confidence: float | None
    confidence_factors: tuple[ConfidenceFactor, ...]
    normalized_text_sha256: str | None
    normalized_character_count: int
    expected_terms: tuple[str, ...]
    matched_terms: tuple[str, ...]

    def to_dict(self) -> dict[str, Any]:
        return asdict(self)
