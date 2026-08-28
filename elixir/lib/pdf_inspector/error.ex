defmodule PdfInspector.Error do
  @moduledoc """
  Error payload of every `PdfInspector` function (`{:error, %__MODULE__{}}`).

  `code` is one of `:io`, `:parse`, `:encrypted`, `:invalid_structure`,
  `:not_a_pdf`, `:internal_panic` (the last means a panic was caught at the
  FFI boundary — it never unwinds into the VM).
  """

  @type code :: :io | :parse | :encrypted | :invalid_structure | :not_a_pdf | :internal_panic
  @type t :: %__MODULE__{code: code(), message: String.t()}

  defstruct [:code, :message]
end
