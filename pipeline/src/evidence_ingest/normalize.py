from __future__ import annotations

import re
import unicodedata


def normalize_text(text: str) -> str:
    text = unicodedata.normalize("NFC", text)
    text = text.replace("\r\n", "\n").replace("\r", "\n")
    text = "".join(char for char in text if char in "\n\t" or ord(char) >= 32)
    text = re.sub(r"[ \t]+", " ", text)
    text = re.sub(r" *\n *", "\n", text)
    text = re.sub(r"\n{3,}", "\n\n", text)
    return text.strip()


def split_units(text: str) -> list[str]:
    normalized = normalize_text(text)
    if not normalized:
        return []
    blocks = [block.strip() for block in re.split(r"\n\s*\n", normalized) if block.strip()]
    if len(blocks) == 1:
        blocks = [line.strip() for line in normalized.splitlines() if line.strip()]
    return blocks
