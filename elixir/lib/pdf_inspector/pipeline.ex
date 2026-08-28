defmodule PdfInspector.Pipeline.Ocr do
  @moduledoc """
  Behaviour for OCR handoff modules used by the `{:ocr, module}` strategy.

  `extract/2` receives the original PDF binary and the **0-indexed** list of
  pages that need OCR, and returns `%{page => markdown_text}`. Pages missing
  from the map keep their placeholder (`needs_ocr: true`). Returning
  `{:error, reason}` leaves the per-page placeholders untouched and records
  `reason` in `result.ocr_errors` — classification/extraction results are
  not discarded.
  """

  @callback extract(binary(), [non_neg_integer()]) ::
              {:ok, %{non_neg_integer() => String.t()}} | {:error, term()}
end

defmodule PdfInspector.Pipeline.Result do
  @moduledoc """
  Aggregated result of a `PdfInspector.Pipeline` run.

  All page numbers (`classification.pages_needing_ocr`, per-page `page`,
  `ocr_pages`) are **0-indexed** (upstream convention). See
  `PdfInspector.Pipeline` for the `markdown` field's join semantics.
  """

  alias PdfInspector.{Classification, PageMarkdown}

  @type strategy :: :markdown | :pages | :classify | :skip | :ocr

  @type t :: %__MODULE__{
          classification: Classification.t(),
          strategy: strategy(),
          markdown: String.t() | nil,
          pages: [PageMarkdown.t()] | nil,
          ocr_pages: [non_neg_integer()],
          ocr_errors: term() | nil
        }

  defstruct [:classification, :strategy, :markdown, :pages, ocr_pages: [], ocr_errors: nil]
end

defmodule PdfInspector.Pipeline do
  @moduledoc """
  Declarative routing pipeline DSL on top of `PdfInspector`:
  classify once, dispatch to a per-`pdf_type` strategy, aggregate.

  ## Example

      defmodule MyApp.DocPipeline do
        use PdfInspector.Pipeline

        route :text_based, :markdown          # process/1 → full-doc markdown
        route :mixed,      :pages             # extract_pages/2 → per-page markdown
        route :scanned,    {:ocr, MyApp.Ocr}  # hand OCR pages to an Ocr behaviour impl
        route :image_based, :skip             # classification only, no content

        fallback :classify                    # optional; default :classify
      end

      MyApp.DocPipeline.run(binary)
      #=> {:ok, %PdfInspector.Pipeline.Result{}} | {:error, %PdfInspector.Error{}}

  ## Strategies

    * `:markdown` — `PdfInspector.process/1`, full-document markdown.
    * `:pages` — `PdfInspector.extract_pages/2` (all pages), per-page markdown;
      pages flagged `needs_ocr` stay as placeholders and are listed in
      `result.ocr_pages`.
    * `:classify` — classification only.
    * `:skip` — classification only, but marks the type as deliberately
      skipped (distinct from the fallback).
    * `{:ocr, module}` — `extract_pages/2` first, then pages needing OCR are
      handed to `module.extract(binary, pages)` (see `PdfInspector.Pipeline.Ocr`);
      returned texts are merged into the corresponding pages.

  ## Page indexing (upstream convention, unchanged)

  `result.classification.pages_needing_ocr`, per-page `page` numbers,
  `result.ocr_pages` and the `pages` argument of the OCR callback are all
  **0-indexed**.

  `result.markdown` for `:pages` / `:ocr` strategies is a convenience join of
  the per-page markdowns with `"\\n\\n"` — the authoritative content is
  `result.pages` (it is *not* guaranteed byte-identical to the `:markdown`
  strategy's full-document output).

  Classification errors (e.g. `:encrypted`) are propagated as
  `{:error, %PdfInspector.Error{}}` without entering any strategy.
  """

  alias PdfInspector.{Classification, Error, PageMarkdown, Pipeline.Result}

  @pdf_types [:text_based, :scanned, :image_based, :mixed]
  @atom_strategies [:markdown, :pages, :classify, :skip]

  defmacro __using__(_opts) do
    quote do
      import PdfInspector.Pipeline, only: [route: 2, fallback: 1]

      Module.register_attribute(__MODULE__, :pdf_pipeline_routes, accumulate: true)
      Module.register_attribute(__MODULE__, :pdf_pipeline_fallback, accumulate: false)

      @before_compile PdfInspector.Pipeline
    end
  end

  @doc "Route a `pdf_type` to a strategy. See the moduledoc for the strategy list."
  defmacro route(pdf_type, strategy) do
    strategy = expand_strategy(strategy, __CALLER__)

    quote bind_quoted: [pdf_type: pdf_type, strategy: Macro.escape(strategy)] do
      PdfInspector.Pipeline.__route__(__MODULE__, pdf_type, strategy)
    end
  end

  @doc "Strategy for pdf_types without an explicit `route/2` (default `:classify`)."
  defmacro fallback(strategy) do
    strategy = expand_strategy(strategy, __CALLER__)

    quote bind_quoted: [strategy: Macro.escape(strategy)] do
      PdfInspector.Pipeline.__fallback__(__MODULE__, strategy)
    end
  end

  defp expand_strategy({:ocr, module_ast}, env), do: {:ocr, Macro.expand(module_ast, env)}
  defp expand_strategy(other, _env), do: other

  @doc false
  def __route__(module, pdf_type, strategy) do
    unless pdf_type in @pdf_types do
      raise ArgumentError,
            "unknown pdf_type #{inspect(pdf_type)}, expected one of #{inspect(@pdf_types)}"
    end

    validate_strategy!(strategy)

    routes = Module.get_attribute(module, :pdf_pipeline_routes) || []

    if Enum.any?(routes, fn {t, _} -> t == pdf_type end) do
      raise ArgumentError, "duplicate route for pdf_type #{inspect(pdf_type)}"
    end

    Module.put_attribute(module, :pdf_pipeline_routes, {pdf_type, strategy})
  end

  @doc false
  def __fallback__(module, strategy) do
    validate_strategy!(strategy)

    if Module.get_attribute(module, :pdf_pipeline_fallback) != nil do
      raise ArgumentError, "fallback already set"
    end

    Module.put_attribute(module, :pdf_pipeline_fallback, strategy)
  end

  defp validate_strategy!(strategy) when strategy in @atom_strategies, do: :ok

  defp validate_strategy!({:ocr, module}) when is_atom(module) do
    unless Code.ensure_loaded?(module) and function_exported?(module, :extract, 2) do
      raise ArgumentError,
            "{:ocr, #{inspect(module)}} requires #{inspect(module)}.extract/2 " <>
              "(see PdfInspector.Pipeline.Ocr)"
    end

    :ok
  end

  defp validate_strategy!(other) do
    raise ArgumentError,
          "invalid strategy #{inspect(other)}, expected one of " <>
            "#{inspect(@atom_strategies)} or {:ocr, module}"
  end

  defmacro __before_compile__(env) do
    routes =
      env.module
      |> Module.get_attribute(:pdf_pipeline_routes)
      |> Enum.reverse()
      |> Map.new()

    fallback = Module.get_attribute(env.module, :pdf_pipeline_fallback) || :classify

    quote do
      @doc "The compiled routing table, `%{pdf_type => strategy}`."
      def routes, do: unquote(Macro.escape(routes))

      @doc "The fallback strategy for unrouted pdf_types."
      def fallback, do: unquote(fallback)

      @doc "The strategy a given `pdf_type` routes to."
      def strategy_for(pdf_type), do: Map.get(routes(), pdf_type, fallback())

      @doc """
      Run the pipeline on a PDF binary.

      Returns `{:ok, %PdfInspector.Pipeline.Result{}}` or
      `{:error, %PdfInspector.Error{}}` (classification errors propagate).
      """
      @spec run(binary()) ::
              {:ok, PdfInspector.Pipeline.Result.t()} | {:error, PdfInspector.Error.t()}
      def run(binary) when is_binary(binary) do
        PdfInspector.Pipeline.__run__(__MODULE__, binary)
      end
    end
  end

  @doc false
  @spec __run__(module(), binary()) :: {:ok, Result.t()} | {:error, Error.t()}
  def __run__(pipeline, binary) do
    with {:ok, %Classification{} = classification} <- PdfInspector.classify(binary) do
      strategy = pipeline.strategy_for(classification.pdf_type)
      execute(strategy, binary, classification)
    end
  end

  defp execute(:markdown, binary, classification) do
    case PdfInspector.process(binary) do
      {:ok, result} ->
        {:ok,
         %Result{
           classification: classification,
           strategy: :markdown,
           markdown: result.markdown,
           ocr_pages: classification.pages_needing_ocr
         }}

      {:error, _} = error ->
        error
    end
  end

  defp execute(:pages, binary, classification) do
    case PdfInspector.extract_pages(binary) do
      {:ok, %{pages: pages}} ->
        {:ok,
         %Result{
           classification: classification,
           strategy: :pages,
           markdown: join_pages(pages),
           pages: pages,
           ocr_pages: ocr_pages(pages)
         }}

      {:error, _} = error ->
        error
    end
  end

  defp execute(:classify, _binary, classification) do
    {:ok,
     %Result{
       classification: classification,
       strategy: :classify,
       ocr_pages: classification.pages_needing_ocr
     }}
  end

  defp execute(:skip, _binary, classification) do
    {:ok,
     %Result{
       classification: classification,
       strategy: :skip,
       ocr_pages: classification.pages_needing_ocr
     }}
  end

  defp execute({:ocr, module}, binary, classification) do
    case PdfInspector.extract_pages(binary) do
      {:ok, %{pages: pages}} ->
        needed = ocr_pages(pages)

        case module.extract(binary, needed) do
          {:ok, texts} when is_map(texts) ->
            merged = merge_ocr_texts(pages, texts)

            {:ok,
             %Result{
               classification: classification,
               strategy: :ocr,
               markdown: join_pages(merged),
               pages: merged,
               ocr_pages: ocr_pages(merged)
             }}

          {:error, reason} ->
            {:ok,
             %Result{
               classification: classification,
               strategy: :ocr,
               markdown: join_pages(pages),
               pages: pages,
               ocr_pages: needed,
               ocr_errors: reason
             }}
        end

      {:error, _} = error ->
        error
    end
  end

  defp ocr_pages(pages), do: for(%PageMarkdown{needs_ocr: true} = p <- pages, do: p.page)

  defp merge_ocr_texts(pages, texts) do
    Enum.map(pages, fn
      %PageMarkdown{needs_ocr: true} = p when is_map_key(texts, p.page) ->
        %{p | markdown: Map.fetch!(texts, p.page), needs_ocr: false}

      p ->
        p
    end)
  end

  defp join_pages(pages) do
    pages
    |> Enum.map(& &1.markdown)
    |> Enum.reject(&(&1 == ""))
    |> Enum.join("\n\n")
  end
end
