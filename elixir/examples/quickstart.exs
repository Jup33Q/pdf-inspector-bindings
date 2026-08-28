# PdfInspector quickstart — the four entry points on the bundled fixtures.
#
# Run from the elixir/ directory:
#
#     PDF_INSPECTOR_EX_BUILD=1 mix run examples/quickstart.exs
#
# (PDF_INSPECTOR_EX_BUILD=1 forces a source build of the NIF; it is required
# until the release CI publishes precompiled artifacts.)

fixtures = Path.expand("../../fixtures", __DIR__)
normal = File.read!(Path.join(fixtures, "normal.pdf"))

IO.puts("== classify/1 (lightest routing entry, 0-indexed pages) ==")
{:ok, c} = PdfInspector.classify(normal)
IO.inspect({c.pdf_type, c.page_count, c.pages_needing_ocr}, label: "type/pages/needs_ocr")

IO.puts("\n== detect/1 (classification + layout, no markdown) ==")
{:ok, d} = PdfInspector.detect(normal)
IO.inspect({d.pdf_type, d.markdown, d.is_complex}, label: "type/markdown/complex")

IO.puts("\n== process/1 (full pipeline with markdown) ==")
{:ok, r} = PdfInspector.process(normal)
IO.inspect({r.pdf_type, r.page_count, byte_size(r.markdown), r.title},
  label: "type/pages/markdown_bytes/title"
)

IO.puts("\n== extract_pages/2 (per-page markdown, 0-indexed) ==")
{:ok, all} = PdfInspector.extract_pages(normal)
IO.inspect(Enum.map(all.pages, & &1.page), label: "nil -> all pages")

{:ok, one} = PdfInspector.extract_pages(normal, [1])
IO.inspect(Enum.map(one.pages, &{&1.page, byte_size(&1.markdown)}), label: "[1] -> page 1 only")

{:ok, oob} = PdfInspector.extract_pages(normal, [99])
IO.inspect(Enum.map(oob.pages, &{&1.page, &1.markdown, &1.needs_ocr}),
  label: "[99] -> out-of-range placeholder"
)

IO.puts("\n== error handling ==")
for {name, expected} <- [
      {"encrypted.pdf", :encrypted},
      {"truncated.pdf", :invalid_structure},
      {"garbage.bin", :not_a_pdf}
    ] do
  case PdfInspector.process(File.read!(Path.join(fixtures, name))) do
    {:error, %PdfInspector.Error{code: ^expected, message: msg}} ->
      IO.puts("  #{name} -> {:error, %PdfInspector.Error{code: :#{expected}}} (#{msg})")

    other ->
      IO.puts("  #{name} -> UNEXPECTED: #{inspect(other)}")
  end
end
