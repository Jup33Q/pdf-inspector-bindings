defmodule PdfInspector.MixProject do
  use Mix.Project

  @version "0.1.0"
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
      {:rustler_precompiled, "~> 0.9"}
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
      files: ~w(lib native .formatter.exs mix.exs README.md LICENSE checksum-*.exs)
    ]
  end
end
