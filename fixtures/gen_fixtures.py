#!/usr/bin/env python3
"""Generate test PDF fixtures for pdf-inspector-bindings.

Usage:  .venv/bin/python fixtures/gen_fixtures.py
Output: fixtures/*.pdf + fixtures/garbage.bin

Fixtures:
  normal.pdf       2-page text-based PDF (headings, body, code block)
  encrypted.pdf    user-password encrypted PDF (password: "ffi-test")
  truncated.pdf    first 60% of normal.pdf (valid header, cut xref)
  garbage.bin      random non-PDF bytes
"""
from pathlib import Path

from reportlab.lib import pdfencrypt
from reportlab.lib.pagesizes import letter
from reportlab.pdfgen import canvas

HERE = Path(__file__).resolve().parent


def build_normal(path: Path, encrypt=None) -> None:
    c = canvas.Canvas(str(path), pagesize=letter, encrypt=encrypt)
    c.setTitle("ffi-core fixture")

    # Page 1: heading + body + monospace code block
    c.setFont("Helvetica-Bold", 24)
    c.drawString(72, 720, "FFI Core Fixture")
    c.setFont("Helvetica", 12)
    c.drawString(72, 690, "Text-based PDF for pdf-inspector bindings tests.")
    c.drawString(72, 674, "Covers classification, extraction and markdown conversion.")
    c.setFont("Courier", 10)
    c.drawString(72, 640, "let fixture = build_normal(path);")
    c.showPage()

    # Page 2: second heading + body
    c.setFont("Helvetica-Bold", 18)
    c.drawString(72, 720, "Second Page Heading")
    c.setFont("Helvetica", 12)
    c.drawString(72, 690, "Second page body text for multi-page detection.")
    c.showPage()

    c.save()


def main() -> None:
    normal = HERE / "normal.pdf"
    build_normal(normal)

    enc = pdfencrypt.StandardEncryption("ffi-test", canPrint=1, canModify=0)
    build_normal(HERE / "encrypted.pdf", encrypt=enc)

    data = normal.read_bytes()
    (HERE / "truncated.pdf").write_bytes(data[: int(len(data) * 0.6)])

    import random

    rng = random.Random(42)
    (HERE / "garbage.bin").write_bytes(bytes(rng.randrange(256) for _ in range(2048)))

    for f in sorted(HERE.iterdir()):
        if f.suffix in {".pdf", ".bin"}:
            print(f"{f.name}: {f.stat().st_size} bytes")


if __name__ == "__main__":
    main()
