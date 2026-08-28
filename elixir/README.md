# PdfInspector (`pdf_inspector_ex`)

Elixir bindings for [firecrawl/pdf-inspector](https://github.com/firecrawl/pdf-inspector)
— PDF type classification and markdown extraction — via Rustler **dirty-CPU NIFs**
over the shared `ffi-core` facade (mem-only API: input is always a binary,
file IO stays in Elixir).

```elixir
{:ok, result} = PdfInspector.process(File.read!("document.pdf"))
result.pdf_type           # :text_based | :scanned | :image_based | :mixed
result.markdown           # full-document markdown
result.pages_needing_ocr  # 1-indexed page list

{:ok, classification} = PdfInspector.classify(binary)   # lightest routing entry
{:ok, pages} = PdfInspector.extract_pages(binary)       # per-page markdown + needs_ocr
{:ok, pages} = PdfInspector.extract_pages(binary, [0, 2])  # 0-indexed page list

{:error, %PdfInspector.Error{code: :encrypted}} = PdfInspector.process(encrypted)
```

Error codes: `:io | :parse | :encrypted | :invalid_structure | :not_a_pdf | :internal_panic`.

**Page indexing** (upstream convention, kept as-is): `classify/1` and per-page
entries are **0-indexed**; process-level page lists in `%PdfInspector.Result{}`
are **1-indexed**. Out-of-range pages return empty-markdown /
`needs_ocr: true` placeholders.

## Installation

```elixir
def deps do
  [
    {:pdf_inspector_ex, "~> 0.1.0"}
  ]
end
```

The package ships precompiled NIFs (via `rustler_precompiled`) for
`aarch64-apple-darwin`, `x86_64-apple-darwin`, `x86_64-unknown-linux-gnu` and
`aarch64-unknown-linux-gnu` — no Rust toolchain needed. To force a source
build (required until the release CI publishes artifacts):

```bash
export PDF_INSPECTOR_EX_BUILD=1
mix deps.get && mix compile
```

## Examples

- **LiveBook**: [`livebook/pdf_inspector.livemd`](livebook/pdf_inspector.livemd)
  (also rendered on hexdocs with a *Run in Livebook* badge) — full walkthrough:
  four entry points, error handling, and the Pipeline DSL.
- **`.exs` scripts** (in this repo, run from `elixir/`):

  ```bash
  PDF_INSPECTOR_EX_BUILD=1 mix run examples/quickstart.exs     # four entry points + errors
  PDF_INSPECTOR_EX_BUILD=1 mix run examples/pipeline_dsl.exs   # Pipeline DSL + OCR handoff
  ```

- **iex**:

  ```elixir
  iex> {:ok, r} = PdfInspector.process(File.read!("../fixtures/normal.pdf"))
  iex> r.pdf_type
  :text_based
  iex> {:ok, c} = PdfInspector.classify(File.read!("../fixtures/normal.pdf"))
  iex> c.pages_needing_ocr   # 0-indexed
  []
  ```

## Development (this monorepo)

```bash
cd elixir
mix deps.get
mix test   # builds native/pdf_inspector_nif with cargo on first run
```

All four NIFs (`process/1`, `detect/1`, `classify/1`, `extract_pages/2`) are
scheduled `DirtyCpu` — extraction takes 10–200 ms, far beyond the 1 ms
normal-NIF budget.

## Pipeline DSL

`PdfInspector.Pipeline` is a declarative classify → route → extract →
aggregate layer (pure Elixir, no extra deps):

```elixir
defmodule MyApp.DocPipeline do
  use PdfInspector.Pipeline

  route :text_based, :markdown          # process/1 → full-doc markdown
  route :mixed,      :pages             # extract_pages/2 → per-page markdown
  route :scanned,    {:ocr, MyApp.Ocr}  # hand OCR pages to an Ocr behaviour impl
  route :image_based, :skip             # classification only

  fallback :classify                    # optional, default :classify
end

{:ok, result} = MyApp.DocPipeline.run(binary)
result.strategy        # which route fired
result.markdown        # full-doc (:markdown) or per-page join (:pages/:ocr)
result.pages           # per-page results for :pages/:ocr
result.ocr_pages       # 0-indexed pages still needing OCR
result.ocr_errors      # OCR callback error, if any (extraction results kept)
```

Types/strategies are validated at compile time (unknown pdf_type, duplicate
route, invalid strategy all raise). `{:ocr, module}` requires
`module.extract(binary, pages_0_indexed) :: {:ok, %{page => text}} | {:error, term()}`
(see `PdfInspector.Pipeline.Ocr`); returned texts are merged into the
placeholder pages. Classification errors (`:encrypted` etc.) propagate
without entering any strategy. All page numbers stay 0-indexed (upstream
convention).
