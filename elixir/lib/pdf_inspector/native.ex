defmodule PdfInspector.Native do
  @moduledoc false

  version = Mix.Project.config()[:version]

  # RustlerPrecompiled standard wiring: download a precompiled NIF per target
  # from the GitHub release, falling back to building from source. The
  # precompiled artifacts themselves are produced by CI (P3); during
  # development `PDF_INSPECTOR_EX_BUILD=1` (or a missing release artifact)
  # always compiles `native/pdf_inspector_nif` with cargo.
  use RustlerPrecompiled,
    otp_app: :pdf_inspector_ex,
    crate: "pdf_inspector_nif",
    base_url: "https://github.com/jup33q/pdf-inspector-bindings/releases/download/v#{version}",
    force_build: System.get_env("PDF_INSPECTOR_EX_BUILD") in ["1", "true"],
    version: version,
    targets: ~w(
      aarch64-apple-darwin
      x86_64-apple-darwin
      x86_64-unknown-linux-gnu
      aarch64-unknown-linux-gnu
    )

  defp err, do: :erlang.nif_error(:nif_not_loaded)

  def process(_data), do: err()
  def detect(_data), do: err()
  def classify(_data), do: err()
  def extract_pages(_data, _pages), do: err()
end
