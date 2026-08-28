defmodule PdfInspector.PipelineTest do
  use ExUnit.Case, async: true

  alias PdfInspector.{Error, PageMarkdown}
  alias PdfInspector.Pipeline.Result

  @fixtures_dir Path.expand("../../../fixtures", __DIR__)

  defp fixture(name), do: File.read!(Path.join(@fixtures_dir, name))

  # --- Test pipelines -------------------------------------------------------

  defmodule SpyOcr do
    @behaviour PdfInspector.Pipeline.Ocr

    @impl true
    def extract(binary, pages) do
      send(self(), {:spy_ocr_called, byte_size(binary), pages})
      {:ok, %{}}
    end
  end

  defmodule FailingOcr do
    @behaviour PdfInspector.Pipeline.Ocr

    @impl true
    def extract(_binary, _pages), do: {:error, :no_ocr_available}
  end

  defmodule MarkdownPipeline do
    use PdfInspector.Pipeline

    route(:text_based, :markdown)
    fallback(:classify)
  end

  defmodule PagesPipeline do
    use PdfInspector.Pipeline

    route(:text_based, :pages)
    route(:mixed, :pages)
  end

  defmodule OcrPipeline do
    use PdfInspector.Pipeline

    route(:text_based, {:ocr, SpyOcr})
  end

  defmodule FailingOcrPipeline do
    use PdfInspector.Pipeline

    route(:text_based, {:ocr, FailingOcr})
  end

  # --- Compile-time validation ----------------------------------------------

  describe "compile-time validation" do
    test "unknown pdf_type raises" do
      assert_raise ArgumentError, ~r/unknown pdf_type/, fn ->
        Code.compile_string("""
        defmodule BadType do
          use PdfInspector.Pipeline
          route :bogus, :markdown
        end
        """)
      end
    end

    test "duplicate route raises" do
      assert_raise ArgumentError, ~r/duplicate route/, fn ->
        Code.compile_string("""
        defmodule DupRoute do
          use PdfInspector.Pipeline
          route :text_based, :markdown
          route :text_based, :pages
        end
        """)
      end
    end

    test "invalid strategy raises" do
      assert_raise ArgumentError, ~r/invalid strategy/, fn ->
        Code.compile_string("""
        defmodule BadStrategy do
          use PdfInspector.Pipeline
          route :text_based, :bogus
        end
        """)
      end
    end

    test "ocr module without extract/2 raises" do
      assert_raise ArgumentError, ~r/extract\/2/, fn ->
        Code.compile_string("""
        defmodule NoExtract do
          use PdfInspector.Pipeline
          route :scanned, {:ocr, String}
        end
        """)
      end
    end
  end

  # --- Routing table ---------------------------------------------------------

  describe "routing" do
    test "routes/0 and strategy_for/1 reflect the DSL" do
      assert MarkdownPipeline.routes() == %{text_based: :markdown}
      assert MarkdownPipeline.strategy_for(:text_based) == :markdown
      assert MarkdownPipeline.strategy_for(:scanned) == :classify
      assert MarkdownPipeline.fallback() == :classify
    end

    test "default fallback is :classify" do
      assert PagesPipeline.fallback() == :classify
      assert PagesPipeline.strategy_for(:scanned) == :classify
    end
  end

  # --- run/1 -----------------------------------------------------------------

  describe "run/1 :markdown strategy" do
    test "matches PdfInspector.process/1 output on normal.pdf" do
      data = fixture("normal.pdf")

      assert {:ok, %Result{strategy: :markdown} = r} = MarkdownPipeline.run(data)
      assert {:ok, direct} = PdfInspector.process(data)

      assert r.markdown == direct.markdown
      assert r.classification.pdf_type == :text_based
      assert r.ocr_pages == []
      assert r.pages == nil
    end
  end

  describe "run/1 :pages strategy" do
    test "matches PdfInspector.extract_pages/2 on normal.pdf" do
      data = fixture("normal.pdf")

      assert {:ok, %Result{strategy: :pages} = r} = PagesPipeline.run(data)
      assert {:ok, direct} = PdfInspector.extract_pages(data)

      assert r.pages == direct.pages
      assert Enum.map(r.pages, & &1.page) == [0, 1]
      assert r.ocr_pages == []
      assert is_binary(r.markdown)
    end
  end

  describe "run/1 {:ocr, module} strategy" do
    test "hands needs_ocr pages (0-indexed) to the OCR module" do
      data = fixture("normal.pdf")

      assert {:ok, %Result{strategy: :ocr} = r} = OcrPipeline.run(data)
      assert_received {:spy_ocr_called, size, pages}
      assert size == byte_size(data)
      assert pages == []
      assert r.ocr_pages == []
      assert r.ocr_errors == nil
      assert length(r.pages) == 2
    end

    test "OCR {:error, reason} is recorded, extraction results kept" do
      assert {:ok, %Result{strategy: :ocr} = r} =
               FailingOcrPipeline.run(fixture("normal.pdf"))

      assert r.ocr_errors == :no_ocr_available
      assert [%PageMarkdown{}, %PageMarkdown{}] = r.pages
    end
  end

  describe "run/1 error propagation" do
    test "encrypted.pdf propagates {:error, %Error{code: :encrypted}}" do
      assert {:error, %Error{code: :encrypted}} =
               MarkdownPipeline.run(fixture("encrypted.pdf"))
    end

    test "garbage.bin propagates {:error, %Error{code: :not_a_pdf}}" do
      assert {:error, %Error{code: :not_a_pdf}} =
               PagesPipeline.run(fixture("garbage.bin"))
    end
  end
end
