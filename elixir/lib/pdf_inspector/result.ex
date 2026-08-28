defmodule PdfInspector.Result do
  @moduledoc """
  Result of `PdfInspector.process/1` and `PdfInspector.detect/1`.

  `pages_needing_ocr`, `pages_with_tables`, `pages_with_columns` and the
  `page` fields inside `ocr_reasons_by_page` are **1-indexed** (upstream
  process-level convention). `markdown` is `nil` for `detect/1`.
  """

  @type pdf_type :: :text_based | :scanned | :image_based | :mixed

  @type t :: %__MODULE__{
          pdf_type: pdf_type(),
          markdown: String.t() | nil,
          page_count: non_neg_integer(),
          processing_time_ms: non_neg_integer(),
          pages_needing_ocr: [pos_integer()],
          ocr_reasons_by_page: [PdfInspector.PageOcrReasons.t()],
          title: String.t() | nil,
          confidence: float(),
          is_complex: boolean(),
          pages_with_tables: [pos_integer()],
          pages_with_columns: [pos_integer()],
          has_encoding_issues: boolean()
        }

  defstruct [
    :pdf_type,
    :markdown,
    :page_count,
    :processing_time_ms,
    :pages_needing_ocr,
    :ocr_reasons_by_page,
    :title,
    :confidence,
    :is_complex,
    :pages_with_tables,
    :pages_with_columns,
    :has_encoding_issues
  ]
end
