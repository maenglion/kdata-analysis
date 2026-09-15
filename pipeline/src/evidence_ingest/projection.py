from __future__ import annotations

import csv
import json
from pathlib import Path

from .contracts import PUBLISH_CONTRACT_VERSION, PipelineResult
from .hashing import canonical_json_bytes, sha256_bytes
from .normalize import split_units


def build_projection(result: PipelineResult, normalized_text: str) -> dict:
    document_id = f"doc-{result.source_sha256}"
    units = split_units(normalized_text)
    projection = {
        "publish_contract": PUBLISH_CONTRACT_VERSION,
        "document_id": document_id,
        "institution_id": result.institution_id,
        "source_id": result.source_id,
        "source_sha256": result.source_sha256,
        "detected_format": result.detection.container_format,
        "protection_status": result.detection.protection_status,
        "extraction_status": result.extraction.status,
        "extraction_confidence": result.extraction_confidence,
        "extraction_confidence_factors": [
            {
                "code": factor.code,
                "value": factor.value,
                "weight": factor.weight,
                "basis": factor.basis,
            }
            for factor in result.confidence_factors
        ],
        "normalized_text_sha256": result.normalized_text_sha256,
        "unit_count": len(units),
        "parser_version": result.parser_version,
    }
    projection["projection_sha256"] = sha256_bytes(canonical_json_bytes(projection))
    return projection


def write_outputs(result: PipelineResult, normalized_text: str, output_root: Path) -> dict[str, Path]:
    internal_dir = output_root / "internal"
    publish_dir = output_root / "publish"
    internal_dir.mkdir(parents=True, exist_ok=True)
    publish_dir.mkdir(parents=True, exist_ok=True)
    projection = build_projection(result, normalized_text)
    units = split_units(normalized_text)

    manifest_path = internal_dir / "runtime-manifest.json"
    document_path = publish_dir / "publish-document.json"
    text_path = internal_dir / "normalized-text.txt"
    units_path = internal_dir / "parsed-units.csv"

    manifest_path.write_bytes(canonical_json_bytes(result.to_dict()) + b"\n")
    document_path.write_bytes(canonical_json_bytes(projection) + b"\n")
    text_path.write_text(normalized_text, encoding="utf-8", newline="\n")
    with units_path.open("w", encoding="utf-8", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=["unit_id", "document_id", "sequence", "text_sha256", "text"])
        writer.writeheader()
        for index, unit in enumerate(units, 1):
            writer.writerow(
                {
                    "unit_id": f"{projection['document_id']}-u{index:05d}",
                    "document_id": projection["document_id"],
                    "sequence": index,
                    "text_sha256": sha256_bytes(unit.encode("utf-8")),
                    "text": unit,
                }
            )
    return {
        "manifest": manifest_path,
        "document": document_path,
        "text": text_path,
        "units": units_path,
    }
