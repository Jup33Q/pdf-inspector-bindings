defmodule PdfInspector do
  @moduledoc """
  Elixir bindings for the [`pdf-inspector`](https://github.com/firecrawl/pdf-inspector)
  PDF classification / markdown-extraction library (Rustler dirty-CPU NIFs over
  the shared `ffi-core` facade).

  All functions take the PDF contents as a **binary** — file IO is the
  caller's job — and return `{:ok, result}` or
  `{:error, %PdfInspector.Error{code: code, message: message}}` where `code`
  is one of `:io`, `:parse`, `:encrypted`, `:invalid_structure`,
  `:not_a_pdf`, `:internal_panic`.

  ## Page indexing (upstream convention, kept as-is)

    * `classify/1` and per-page entries (`%PdfInspector.PageMarkdown{page: n}`,
      `%PdfInspector.PageOcrReasons{page: n}` inside `%PdfInspector.PagesResult{}`)
      are **0-indexed**. The `pages` argument of `extract_pages/2` is also
      0-indexed; `nil` extracts every page in document order.
    * Process-level page lists (`pages_needing_ocr`, `pages_with_tables`,
      `pages_with_columns`, and `ocr_reasons_by_page` in `%PdfInspector.Result{}`)
      are **1-indexed**.

  Requesting an out-of-range page does not error: the entry comes back with
  empty `markdown` and `needs_ocr: true` (upstream placeholder behaviour).

  All NIFs run on dirty-CPU schedulers (extraction takes 10–200 ms, far past
  the 1 ms normal-NIF budget), so calling them never stalls the BEAM.
  """

  alias PdfInspector.{Classification, Error, Native, PagesResult, Result}

  @typedoc "PDF contents as an in-memory binary."
  @type pdf_binary :: binary()

  @doc """
  Full pipeline: classify the document and extract markdown for every page.

      iex> {:ok, %PdfInspector.Result{pdf_type: :text_based}} =
      ...>   PdfInspector.process(File.read!("document.pdf"))

  """
  @spec process(pdf_binary()) :: {:ok, Result.t()} | {:error, Error.t()}
  def process(data) when is_binary(data), do: Native.process(data)

  @doc """
  Detection-only pipeline: classification + layout, no markdown
  (`%PdfInspector.Result{markdown: nil}`).
  """
  @spec detect(pdf_binary()) :: {:ok, Result.t()} | {:error, Error.t()}
  def detect(data) when is_binary(data), do: Native.detect(data)

  @doc """
  Lightest routing entry: PDF type + confidence + pages needing OCR
  (**0-indexed**).
  """
  @spec classify(pdf_binary()) :: {:ok, Classification.t()} | {:error, Error.t()}
  def classify(data) when is_binary(data), do: Native.classify(data)

  @doc """
  Per-page markdown for hybrid pipelines.

  `pages` is a list of **0-indexed** page numbers; `nil` (the default)
  extracts every page in document order. Out-of-range pages come back as
  empty-markdown / `needs_ocr: true` placeholders.
  """
  @spec extract_pages(pdf_binary(), [non_neg_integer()] | nil) ::
          {:ok, PagesResult.t()} | {:error, Error.t()}
  def extract_pages(data, pages \\ nil)
      when is_binary(data) and (is_nil(pages) or is_list(pages)),
      do: Native.extract_pages(data, pages)
end
