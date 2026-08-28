# pdf-inspector-bindings

Self-built Swift / Elixir bindings for [firecrawl/pdf-inspector](https://github.com/firecrawl/pdf-inspector)
(crates.io release, pinned `~1.17`, no upstream fork).

Design: bindings only expose the **mem-only** API — input is always `&[u8]`
(Swift `Data` / Elixir binary pass straight through), file IO stays in the
host language. See the Obsidian plan:
`02-Projects/pdf-inspector/绑定自实现方案与重构计划.md`.

## Layout

```
ffi-core/    P0+P1 FFI facade crate (cdylib + staticlib + rlib, UniFFI proc-macro)
swift/       P1 UniFFI + XCFramework SwiftPM package (PdfInspectorSwift)
swift/Demo/  macOS CLI smoke test for the XCFramework path
elixir/      P2 Rustler dirty_cpu NIF Hex package (pdf_inspector_ex)
fixtures/    test PDFs, regenerate with gen_fixtures.py
scripts/     compare_with_cli.py — output alignment vs official CLIs
```

## ffi-core (P0, done)

Flat API, all entries `catch_unwind`-guarded (panic → `FfiErrorCode::InternalPanic`,
never unwinds across FFI):

| Function | Input | Output |
|---|---|---|
| `process_pdf_mem` | `&[u8]` | `FfiProcessResult` (with markdown) |
| `detect_pdf_mem` | `&[u8]` | `FfiProcessResult` (no markdown) |
| `classify_pdf_mem` | `&[u8]` | `FfiClassification` (lightest routing entry) |
| `extract_pages_markdown_mem` | `&[u8]` + `Option<&[u32]>` (0-indexed pages) | `FfiPagesResult` |

Result structs use only the UniFFI Record / Rustler NifStruct common subset
(no nested records; upstream `LayoutComplexity` is flattened into
`FfiProcessResult`). `PdfError` maps to flat `FfiErrorCode`
(Io / Parse / Encrypted / InvalidStructure / NotAPdf / InternalPanic).

Page indexing follows upstream: `classify_pdf_mem` and per-page results are
**0-indexed**; process-level `pages_needing_ocr` / `pages_with_tables` /
`pages_with_columns` / `ocr_reasons_by_page` are **1-indexed**.

## Build & test

```bash
# fixtures (one-time, needs Python venv with reportlab)
python3 -m venv .venv && .venv/bin/pip install reportlab
.venv/bin/python fixtures/gen_fixtures.py

cargo test -p ffi-core                                   # 10 tests
cargo build --release -p ffi-core --example memcli
.venv/bin/python scripts/compare_with_cli.py             # alignment vs pdf2md/detect-pdf
```

Release profile: `lto = "thin"`, `codegen-units = 1`.
Deliberately **no** `panic = "abort"` — `catch_unwind` needs unwinding.

## swift/ (P1, done)

UniFFI 0.32 proc-macro export (`#[uniffi::export]` wrappers over the P0
functions, `uniffi::setup_scaffolding!()`; errors thrown as the
`PdfInspectorError` enum, one case per `FfiErrorCode`). `ffi-core/uniffi.toml`
renames the FFI module to `PdfInspectorFFI` and is auto-discovered by
`uniffi-bindgen` — do **not** pass `--config` (0.32 changed that flag to a
global config format).

```bash
# one-time: CLI matching the uniffi crate version
cargo install uniffi --locked --version 0.32.0 --features cli

swift/build-xcframework.sh   # 4 rust targets + lipo sim → XCFramework + Swift bindings
cd swift/Demo && swift run pdf-inspector-demo ../../fixtures/normal.pdf

# iOS Simulator build check (needs full Xcode; script sets DEVELOPER_DIR itself)
cd swift && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild build -scheme PdfInspectorSwift \
  -destination 'generic/platform=iOS Simulator' -derivedDataPath build/dd
```

Swift API: `PdfInspector.process(data: Data) throws -> PdfProcessResult`
(plus `detect` / `classify` / `extractPagesMarkdown`); the `Ffi*` records are
aliased to `Pdf*` names. `Package.swift` has a `useLocalFramework` toggle —
local dev uses `Frameworks/PdfInspectorFFI.xcframework`; release tags are
rewritten by CI (url + checksum).

Size reality (measured 2026-08): per-arch staticlibs are ~52 MB fat archives
(thin-LTO objects embed bitcode; a static archive cannot dead-strip — Apple
ld forbids `-r -dead_strip`). DCE happens at the final link: the release demo
binary links the whole stack into a 6.0 MB Mach-O. XCFramework zip ≈ 79 MB.
The 1–3 MB per-arch target is not achievable for a static archive; the linked
footprint is the meaningful metric.


## elixir/ (P2, done)

Rustler NIF package `pdf_inspector_ex`: all four entries
(`process/1`, `detect/1`, `classify/1`, `extract_pages/2`) are scheduled
`DirtyCpu` (extraction takes 10–200 ms, far past the 1 ms normal-NIF
budget). The `native/pdf_inspector_nif` crate reuses ffi-core as an rlib
path dependency — pointing at a **vendored copy**
(`elixir/native/ffi-core`, synced from the canonical crate by
`scripts/vendor_ffi_core.sh`, package-renamed to `ffi-core-vendored` to
avoid a Cargo.lock collision) so the hex tarball is self-contained and
source builds work for hex users. Both vendored/NIF Cargo.tomls have
flattened `workspace.package` fields (they must build with no parent
workspace). The UniFFI export layer is untouched and no `extern "C"` is
written by hand. Errors map to
`{:error, %PdfInspector.Error{code: atom, message: String}}` via the
`FfiError` record; result structs mirror the `Ffi*` shapes via `NifStruct`
(`pdf_type` → `:text_based | :scanned | :image_based | :mixed`).

Examples: `elixir/examples/quickstart.exs` + `pipeline_dsl.exs` (runnable
`.exs` scripts) and `elixir/livebook/pdf_inspector.livemd` (LiveBook
notebook, also an ex_doc extra on hexdocs).

```bash
cd elixir
mix deps.get
PDF_INSPECTOR_EX_BUILD=1 mix test   # 25 tests; builds the NIF from source
```

NIF loading follows the standard `rustler_precompiled` wiring (four
targets: aarch64/x86_64 apple-darwin + unknown-linux-gnu,
`PDF_INSPECTOR_EX_BUILD=1` forces a source build). Precompiled artifacts
are P3 CI's job; until the first GitHub release exists, source build is
the only path.

Verified: `mix test` 25/25 (four fixtures + 0/1-indexed page-numbering
cases + the pipeline DSL); iex `PdfInspector.process(File.read!("fixtures/normal.pdf"))`
markdown is byte-identical to `pdf2md --raw`. The loaded NIF
`pdf_inspector_nif.so` is **6.1 MB** and self-contained (ffi-core linked
statically as rlib, final-link DCE — cf. the 52 MB static archive in P1;
same ~6 MB linked footprint as the Swift demo binary). Note: rustler
0.38 also copies sibling workspace artifacts into `priv/native/`
(`ffi_core.so`, an rlib mislabeled `pdf_inspector.so`) — unused noise,
gitignored, only `pdf_inspector_nif.so` is loaded.

### Pipeline DSL (P2 addendum)

`PdfInspector.Pipeline` (pure Elixir, in the same package): declarative
classify → route-per-`pdf_type` → extract/OCR-handoff → aggregate.

```elixir
defmodule MyApp.DocPipeline do
  use PdfInspector.Pipeline
  route :text_based, :markdown          # process/1
  route :mixed,      :pages             # extract_pages/2
  route :scanned,    {:ocr, MyApp.Ocr}  # Ocr behaviour handoff
  fallback :classify
end
MyApp.DocPipeline.run(binary)  #=> {:ok, %PdfInspector.Pipeline.Result{}}
```

Routes/strategies are compile-time validated; `{:ocr, mod}` merges
`mod.extract(binary, pages_0_indexed)` texts into placeholder pages and
records OCR errors in `result.ocr_errors` without discarding extraction
results.
