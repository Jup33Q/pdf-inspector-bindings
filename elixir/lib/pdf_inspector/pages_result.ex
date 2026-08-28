defmodule PdfInspector.PageMarkdown do
  @moduledoc """
  Markdown of a single page (`page` is **0-indexed**).

  An out-of-range page comes back as a placeholder with empty `markdown`
  and `needs_ocr: true` (upstream behaviour, not an error).
  """

  @type t :: %__MODULE__{
          page: non_neg_integer(),
          markdown: String.t(),
          needs_ocr: boolean(),
          ocr_reason: String.t() | nil
        }

  defstruct [:page, :markdown, :needs_ocr, :ocr_reason]
end

defmodule PdfInspector.PageOcrReasons do
  @moduledoc """
  OCR reasons for a single page. The `page` numbering follows the parent
  struct: 1-indexed inside `PdfInspector.Result` / `PdfInspector.PagesResult`
  process-level lists.
  """

  @type t :: %__MODULE__{page: pos_integer(), reasons: [String.t()]}

  defstruct [:page, :reasons]
end

defmodule PdfInspector.PagesResult do
  @moduledoc """
  Result of `PdfInspector.extract_pages/2`.

  `pages` entries carry **0-indexed** `page` numbers, while the
  process-level lists (`pages_needing_ocr`, `pages_with_tables`,
  `pages_with_columns`, `ocr_reasons_by_page`) are **1-indexed**.
  """

  @type t :: %__MODULE__{
          pages: [PdfInspector.PageMarkdown.t()],
          pages_with_tables: [pos_integer()],
          pages_with_columns: [pos_integer()],
          pages_needing_ocr: [pos_integer()],
          ocr_reasons_by_page: [PdfInspector.PageOcrReasons.t()],
          is_complex: boolean()
        }

  defstruct [
    :pages,
    :pages_with_tables,
    :pages_with_columns,
    :pages_needing_ocr,
    :ocr_reasons_by_page,
    :is_complex
  ]
end
