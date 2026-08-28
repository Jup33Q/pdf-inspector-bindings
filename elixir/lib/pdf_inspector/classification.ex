defmodule PdfInspector.Classification do
  @moduledoc """
  Result of `PdfInspector.classify/1` (lightest routing entry).

  `pages_needing_ocr` is **0-indexed** (upstream convention for this entry
  point — unlike the 1-indexed process-level lists in
  `PdfInspector.Result`).
  """

  @type t :: %__MODULE__{
          pdf_type: PdfInspector.Result.pdf_type(),
          page_count: non_neg_integer(),
          pages_needing_ocr: [non_neg_integer()],
          confidence: float()
        }

  defstruct [:pdf_type, :page_count, :pages_needing_ocr, :confidence]
end
