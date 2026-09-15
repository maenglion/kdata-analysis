from __future__ import annotations

import json
import tempfile
import unittest
import zipfile
from datetime import date, timedelta
from pathlib import Path

from evidence_ingest.classify import detect_document
from evidence_ingest.collect import write_public_snapshot
from evidence_ingest.hashing import canonical_json_bytes, sha256_bytes
from evidence_ingest.pipeline import process_file
from evidence_ingest.projection import build_projection, write_outputs
from evidence_ingest.schedule import is_due


class PipelineContractTests(unittest.TestCase):
    def test_hwpx_extraction_and_projection_are_deterministic(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / "sample.hwpx"
            with zipfile.ZipFile(source, "w") as archive:
                archive.writestr("mimetype", "application/hwp+zip")
                archive.writestr(
                    "Contents/section0.xml",
                    '<?xml version="1.0" encoding="UTF-8"?>'
                    '<hp:sec xmlns:hp="urn:hancom:section"><hp:t>데이터바우처</hp:t>'
                    '<hp:t>정보공개</hp:t></hp:sec>',
                )

            result, text = process_file(
                source,
                institution_id="kdata",
                source_id="TEST-HWPX",
                expected_terms=("데이터바우처", "정보공개"),
            )
            first = build_projection(result, text)
            second = build_projection(result, text)
            schema = json.loads(
                (Path(__file__).parents[1] / "schemas" / "publish-document.v1.schema.json").read_text(encoding="utf-8")
            )
            runtime_schema = json.loads(
                (Path(__file__).parents[1] / "schemas" / "runtime-contract.v1.schema.json").read_text(encoding="utf-8")
            )

            self.assertEqual(result.detection.container_format, "hwpx")
            self.assertEqual(result.extraction.status, "extracted")
            self.assertEqual(result.matched_terms, ("데이터바우처", "정보공개"))
            self.assertEqual(first, second)
            self.assertTrue(set(schema["required"]).issubset(first))
            self.assertTrue(set(first).issubset(schema["properties"]))
            self.assertTrue(set(runtime_schema["required"]).issubset(result.to_dict()))
            self.assertTrue(set(result.to_dict()).issubset(runtime_schema["properties"]))
            self.assertEqual(len(first["source_sha256"]), 64)
            self.assertEqual(len(first["projection_sha256"]), 64)
            unsigned = {key: value for key, value in first.items() if key != "projection_sha256"}
            self.assertEqual(first["projection_sha256"], sha256_bytes(canonical_json_bytes(unsigned)))

    def test_protected_wrappers_are_classified_without_extraction(self) -> None:
        for vendor, payload in (
            ("DRMONE", b"wrapper DRMONE protected payload"),
            ("FASOO", b"wrapper FASOO DRM protected payload"),
        ):
            with self.subTest(vendor=vendor), tempfile.TemporaryDirectory() as directory:
                source = Path(directory) / "protected.hwp"
                source.write_bytes(payload)
                result, text = process_file(source, institution_id="kdata", source_id=f"TEST-{vendor}")
                self.assertEqual(result.detection.drm_vendor, vendor)
                self.assertEqual(result.detection.protection_status, "protected")
                self.assertEqual(result.extraction.status, "protected")
                self.assertEqual(result.extraction_confidence, None)
                self.assertEqual(text, "")

    def test_internal_text_is_separated_from_public_projection(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / "source.txt"
            source.write_text("민감할 수 있는 전문", encoding="utf-8")
            result, text = process_file(source, institution_id="kdata", source_id="TEST-TEXT")
            paths = write_outputs(result, text, root / "out")
            public_record = json.loads(paths["document"].read_text(encoding="utf-8"))

            self.assertEqual(paths["document"].parent.name, "publish")
            self.assertEqual(paths["text"].parent.name, "internal")
            self.assertNotIn("text", public_record)
            self.assertNotIn("source_locator", public_record)
            self.assertNotIn("source_filename", public_record)
            self.assertNotIn(str(root), paths["document"].read_text(encoding="utf-8"))

    def test_exact_ten_day_schedule_crosses_month_boundaries(self) -> None:
        epoch = date(2026, 9, 15)
        until = date(2028, 9, 15)
        self.assertTrue(is_due(epoch, epoch, 10, until))
        self.assertFalse(is_due(epoch + timedelta(days=9), epoch, 10, until))
        self.assertTrue(is_due(epoch + timedelta(days=10), epoch, 10, until))
        self.assertTrue(is_due(epoch + timedelta(days=20), epoch, 10, until))
        self.assertFalse(is_due(date(2028, 9, 16), epoch, 10, until))

    def test_html_extracts_visible_text_only(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / "page.html"
            source.write_text(
                "<html><style>hidden-css</style><body><h1>조직도</h1><script>hidden-js</script>담당업무</body></html>",
                encoding="utf-8",
            )
            result, text = process_file(source, institution_id="kdata", source_id="TEST-HTML")
            self.assertEqual(result.extraction.status, "extracted")
            self.assertIn("조직도", text)
            self.assertIn("담당업무", text)
            self.assertNotIn("hidden-css", text)
            self.assertNotIn("hidden-js", text)

    def test_pdf_and_hwp_magic_take_precedence_over_extensions(self) -> None:
        pdf = detect_document(Path("wrong.hwp"), b"%PDF-1.7\n")
        hwp = detect_document(Path("right.hwp"), bytes.fromhex("D0CF11E0A1B11AE1") + b"\0" * 32)
        self.assertEqual(pdf.container_format, "pdf")
        self.assertEqual(hwp.container_format, "hwp_ole")

    def test_vendor_word_inside_clear_pdf_does_not_create_false_drm(self) -> None:
        detection = detect_document(Path("report.pdf"), b"%PDF-1.7\nA report mentioning FASOO DRMONE")
        self.assertEqual(detection.container_format, "pdf")
        self.assertEqual(detection.protection_status, "clear")

    def test_public_snapshot_contains_only_safe_projection_and_is_deterministic(self) -> None:
        index = {
            "institution_id": "kdata",
            "documents": [{"requested_url": "https://example.invalid", "final_url": "https://example.invalid", "projection": {"source_sha256": "a" * 64}}],
            "failures": [{"source_id": "page-1", "error_type": "TimeoutError", "message": "local path must not leak"}],
        }
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            first_path = write_public_snapshot(index, root, "2026-09-15")
            first = first_path.read_bytes()
            second_path = write_public_snapshot(index, root, "2026-09-15")
            second = second_path.read_bytes()
            decoded = json.loads(first)
            schema = json.loads(
                (Path(__file__).parents[1] / "schemas" / "public-collection-snapshot.v1.schema.json").read_text(encoding="utf-8")
            )
            self.assertEqual(first, second)
            self.assertTrue(set(schema["required"]).issubset(decoded))
            self.assertTrue(set(decoded).issubset(schema["properties"]))
            self.assertNotIn("message", decoded["failures"][0])
            unsigned = {key: value for key, value in decoded.items() if key != "snapshot_sha256"}
            self.assertEqual(decoded["snapshot_sha256"], sha256_bytes(canonical_json_bytes(unsigned)))


if __name__ == "__main__":
    unittest.main()
