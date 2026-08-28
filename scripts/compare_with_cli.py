#!/usr/bin/env python3
"""Align ffi-core output with the official pdf-inspector CLIs.

Checks, per fixture PDF:
  1. `memcli md` == `pdf2md --raw`          (byte-for-byte markdown)
  2. `memcli detect` pdf_type/page_count == `detect-pdf --json`
  3. error codes on encrypted/truncated inputs

Usage:  .venv/bin/python scripts/compare_with_cli.py
Requires: memcli built (`cargo build --release -p ffi-core --example memcli`),
          pdf2md / detect-pdf on PATH.
"""
import json
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
FIXTURES = ROOT / "fixtures"
MEMCLI = ROOT / "target" / "release" / "examples" / "memcli"

failures = []


def run(cmd):
    return subprocess.run(cmd, capture_output=True, text=False)


def check(name, ok, detail=""):
    print(f"  {'PASS' if ok else 'FAIL'}  {name}" + (f"  ({detail})" if detail else ""))
    if not ok:
        failures.append(name)


for pdf in ["normal.pdf"]:
    print(f"[{pdf}]")

    cli = run(["pdf2md", str(FIXTURES / pdf), "--raw"])
    ffi = run([str(MEMCLI), "md", str(FIXTURES / pdf)])
    check(
        "markdown byte-identical",
        cli.returncode == 0 and ffi.returncode == 0 and cli.stdout == ffi.stdout,
        f"cli={len(cli.stdout)}B ffi={len(ffi.stdout)}B",
    )

    cli = run(["detect-pdf", str(FIXTURES / pdf), "--json"])
    ffi = run([str(MEMCLI), "detect", str(FIXTURES / pdf)])
    if cli.returncode == 0 and ffi.returncode == 0:
        c, f = json.loads(cli.stdout), json.loads(ffi.stdout)
        check(
            "detect pdf_type+page_count",
            c["pdf_type"] == f["pdf_type"] and c["page_count"] == f["page_count"],
            f"cli={c['pdf_type']}/{c['page_count']} ffi={f['pdf_type']}/{f['page_count']}",
        )
        check(
            "detect timing sane",
            c["detection_time_ms"] < 100 and f["processing_time_ms"] < 100,
            f"cli={c['detection_time_ms']}ms ffi={f['processing_time_ms']}ms",
        )
    else:
        check("detect pdf_type+page_count", False, "one side exited non-zero")

    ffi = run([str(MEMCLI), "classify", str(FIXTURES / pdf)])
    f = json.loads(ffi.stdout)
    check("classify agrees with detect", f["pdf_type"] == c["pdf_type"], f["pdf_type"])

print("[encrypted.pdf]")
ffi = run([str(MEMCLI), "classify", str(FIXTURES / "encrypted.pdf")])
f = json.loads(ffi.stdout)
check("encrypted -> code Encrypted", ffi.returncode != 0 and f.get("code") == "Encrypted", ffi.stdout.decode()[:80])

print("[truncated.pdf]")
ffi = run([str(MEMCLI), "pages", str(FIXTURES / "truncated.pdf")])
ok = True
if ffi.returncode == 0:
    f = json.loads(ffi.stdout)  # tolerated: valid header may still parse
else:
    f = json.loads(ffi.stdout)
    ok = f.get("code") in {"Parse", "InvalidStructure", "NotAPdf", "Io"}
check("truncated -> typed error, never panic", ok and f.get("code") != "InternalPanic", ffi.stdout.decode()[:80])

print()
if failures:
    print(f"{len(failures)} check(s) FAILED")
    sys.exit(1)
print("All checks passed.")
