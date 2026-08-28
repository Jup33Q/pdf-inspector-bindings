defmodule PdfInspectorTest do
  use ExUnit.Case, async: true

  alias PdfInspector.{Classification, Error, PageMarkdown, PagesResult, Result}

  @fixtures_dir Path.expand("../../fixtures", __DIR__)

  defp fixture(name), do: File.read!(Path.join(@fixtures_dir, name))

  describe "process/1" do
    test "normal.pdf classifies as text_based with markdown" do
      assert {:ok, %Result{} = r} = PdfInspector.process(fixture("normal.pdf"))
      assert r.pdf_type == :text_based
      assert r.page_count == 2
      assert is_binary(r.markdown)
      assert r.pages_needing_ocr == []
      assert is_float(r.confidence)
      assert is_integer(r.processing_time_ms)
    end

    test "encrypted.pdf returns {:error, %Error{code: :encrypted}}" do
      assert {:error, %Error{code: :encrypted, message: msg}} =
               PdfInspector.process(fixture("encrypted.pdf"))

      assert is_binary(msg)
    end

    test "truncated.pdf returns {:error, %Error{code: :invalid_structure}}" do
      assert {:error, %Error{code: :invalid_structure}} =
               PdfInspector.process(fixture("truncated.pdf"))
    end

    test "garbage.bin returns {:error, %Error{code: :not_a_pdf}}" do
      assert {:error, %Error{code: :not_a_pdf}} =
               PdfInspector.process(fixture("garbage.bin"))
    end

    test "empty input does not crash the VM (caught panic or error tuple)" do
      assert {:error, %Error{code: code}} = PdfInspector.process(<<>>)
      assert code in [:parse, :not_a_pdf, :invalid_structure, :io, :internal_panic]
    end
  end

  describe "detect/1" do
    test "normal.pdf classifies without markdown" do
      assert {:ok, %Result{pdf_type: :text_based, markdown: nil, page_count: 2}} =
               PdfInspector.detect(fixture("normal.pdf"))
    end

    test "garbage.bin errors" do
      assert {:error, %Error{code: :not_a_pdf}} = PdfInspector.detect(fixture("garbage.bin"))
    end
  end

  describe "classify/1" do
    test "normal.pdf returns a Classification with 0-indexed pages_needing_ocr" do
      assert {:ok, %Classification{} = c} = PdfInspector.classify(fixture("normal.pdf"))
      assert c.pdf_type == :text_based
      assert c.page_count == 2
      assert c.pages_needing_ocr == []
      assert is_float(c.confidence)
    end

    test "encrypted.pdf errors" do
      assert {:error, %Error{code: :encrypted}} =
               PdfInspector.classify(fixture("encrypted.pdf"))
    end
  end

  describe "extract_pages/2 page indexing (0-indexed)" do
    setup do
      {:ok, data: fixture("normal.pdf")}
    end

    test "nil extracts every page, 0-indexed page numbers", %{data: data} do
      assert {:ok, %PagesResult{} = r} = PdfInspector.extract_pages(data)
      assert length(r.pages) == 2
      assert Enum.map(r.pages, & &1.page) == [0, 1]
      assert Enum.all?(r.pages, &is_binary(&1.markdown))
    end

    test "explicit page list keeps 0-indexed numbering", %{data: data} do
      assert {:ok, %PagesResult{pages: [%PageMarkdown{page: 1} = p]}} =
               PdfInspector.extract_pages(data, [1])

      assert is_binary(p.markdown)
    end

    test "out-of-range page is a placeholder: empty markdown + needs_ocr", %{data: data} do
      assert {:ok, %PagesResult{pages: [%PageMarkdown{} = p]}} =
               PdfInspector.extract_pages(data, [99])

      assert p.page == 99
      assert p.markdown == ""
      assert p.needs_ocr == true
    end

    test "encrypted.pdf errors" do
      assert {:error, %Error{code: :encrypted}} =
               PdfInspector.extract_pages(fixture("encrypted.pdf"))
    end
  end
end
