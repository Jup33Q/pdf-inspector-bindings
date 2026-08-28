# PdfInspector.Pipeline DSL — declarative classify → route → extract.
#
# Run from the elixir/ directory:
#
#     PDF_INSPECTOR_EX_BUILD=1 mix run examples/pipeline_dsl.exs

defmodule DemoOcr do
  @moduledoc "Ocr behaviour handoff target (spy — no real OCR here)."

  @behaviour PdfInspector.Pipeline.Ocr

  @impl true
  def extract(binary, pages_0_indexed) do
    IO.puts("  [DemoOcr] handoff: #{length(pages_0_indexed)} page(s) " <>
              "#{inspect(pages_0_indexed)} (#{byte_size(binary)} bytes)")

    # Real implementations run an OCR engine here and return
    # {:ok, %{page => text}}; {:error, reason} keeps the extraction
    # results and records the failure in result.ocr_errors.
    {:ok, Map.new(pages_0_indexed, &{&1, "<ocr text for page #{&1}>"})}
  end
end

defmodule DemoPipeline do
  use PdfInspector.Pipeline

  route :text_based, :markdown          # process/1 -> full-document markdown
  route :mixed,      :pages             # extract_pages/2 -> per-page markdown
  route :scanned,    {:ocr, DemoOcr}    # hand needs_ocr pages to DemoOcr
  route :image_based, :skip             # classification only

  fallback :classify                    # optional; :classify is the default
end

fixtures = Path.expand("../../fixtures", __DIR__)
normal = File.read!(Path.join(fixtures, "normal.pdf"))

IO.puts("== DemoPipeline.run(normal.pdf) ==")
{:ok, result} = DemoPipeline.run(normal)

IO.inspect(result.classification.pdf_type, label: "classified as")
IO.inspect(result.strategy, label: "route fired")
IO.inspect(byte_size(result.markdown || ""), label: "markdown bytes")
IO.inspect(result.ocr_pages, label: "ocr_pages (0-indexed)")
IO.inspect(result.ocr_errors, label: "ocr_errors")

IO.puts("\n== classification errors propagate without entering a strategy ==")
encrypted = File.read!(Path.join(fixtures, "encrypted.pdf"))
IO.inspect(DemoPipeline.run(encrypted), label: "run(encrypted.pdf)")
