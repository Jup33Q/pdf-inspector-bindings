defmodule PdfInspector.MixProject do
  use Mix.Project

  @version "0.1.1"
  @source_url "https://github.com/jup33q/pdf-inspector-bindings"

  def project do
    [
      app: :pdf_inspector_ex,
      version: @version,
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      description: description(),
      package: package(),
      deps: deps(),
      source_url: @source_url
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:rustler, "~> 0.38.0", runtime: false},
      {:rustler_precompiled, "~> 0.9"},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false}
    ]
  end

  defp description do
    "Elixir bindings (Rustler dirty-CPU NIF) for the pdf-inspector PDF " <>
      "classification / markdown-extraction library."
  end

  defp package do
    [
      name: "pdf_inspector_ex",
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url},
      # checksum-*.exs is added by P3 (release CI generates it via
      # `mix rustler_precompiled.download` once precompiled artifacts exist).
      files: ~w(lib native .formatter.exs mix.exs README.md LICENSE)
    ]
  end
end
