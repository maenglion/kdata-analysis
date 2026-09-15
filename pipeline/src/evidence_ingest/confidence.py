from __future__ import annotations

import unicodedata

from .contracts import ConfidenceFactor, Detection, Extraction


def _text_quality(text: str) -> float:
    visible = [char for char in text if not char.isspace()]
    if not visible:
        return 0.0
    acceptable = 0
    for char in visible:
        category = unicodedata.category(char)
        if char.isalnum() or category.startswith(("L", "N", "P", "S")):
            acceptable += 1
    ratio = acceptable / len(visible)
    length_factor = min(1.0, len(visible) / 200)
    return round(ratio * length_factor, 6)


def calculate_extraction_confidence(
    detection: Detection,
    extraction: Extraction,
    normalized_text: str,
    expected_terms: tuple[str, ...],
) -> tuple[float | None, tuple[ConfidenceFactor, ...], tuple[str, ...]]:
    if extraction.status in {"protected", "unsupported", "invalid", "parser_unavailable"}:
        return None, (), ()

    completeness = (
        extraction.unit_with_text / extraction.unit_total
        if extraction.unit_total
        else float(bool(normalized_text))
    )
    matched = tuple(sorted(term for term in expected_terms if term and term in normalized_text))
    factors = [
        ConfidenceFactor("format_detection", detection.confidence, 0.30, ";".join(detection.basis)),
        ConfidenceFactor(
            "extraction_completeness",
            round(completeness, 6),
            0.35,
            f"units_with_text={extraction.unit_with_text}/units_total={extraction.unit_total}",
        ),
        ConfidenceFactor("text_quality", _text_quality(normalized_text), 0.20, "unicode-visible-character-ratio-and-length"),
    ]
    if expected_terms:
        factors.append(
            ConfidenceFactor(
                "internal_term_match",
                round(len(matched) / len(expected_terms), 6),
                0.15,
                f"matched={len(matched)}/expected={len(expected_terms)}",
            )
        )
    applicable_weight = sum(factor.weight for factor in factors)
    score = 100 * sum(factor.value * factor.weight for factor in factors) / applicable_weight
    return round(score, 3), tuple(factors), matched
