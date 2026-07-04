defmodule DefLayout.MixProject do
  use Mix.Project

  @version "0.1.1"
  @source_url "https://github.com/aptinio/def_layout"

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  def cli do
    [preferred_envs: [precommit: :test]]
  end

  def project do
    [
      app: :def_layout,
      version: @version,
      elixir: "~> 1.16",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),
      test_coverage: [summary: [threshold: 100]],
      package: package(),
      docs: docs()
    ]
  end

  defp deps do
    [
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.35", only: :dev, runtime: false},
      {:quokka, "~> 2.12", only: [:dev, :test], runtime: false},
      {:stream_data, "~> 1.3", only: [:dev, :test], runtime: false}
    ]
  end

  defp aliases do
    [
      precommit: [
        "deps.unlock --unused",
        "hex.audit",
        "format",
        "compile --warnings-as-errors",
        "credo --format oneline",
        "test --cover"
      ]
    ]
  end

  defp package do
    [
      description:
        "A mix format plugin that lays out a module's functions: callbacks first, public functions alphabetical, each private just below its bottom-most caller.",
      licenses: ["MIT"],
      links: %{
        "GitHub" => @source_url,
        "Changelog" => "https://hexdocs.pm/def_layout/changelog.html"
      },
      files: ~w(lib mix.exs README.md CHANGELOG.md LICENSE)
    ]
  end

  defp docs do
    [
      main: "readme",
      source_ref: "v#{@version}",
      source_url: @source_url,
      extras: ["README.md", "CHANGELOG.md"],
      skip_undefined_reference_warnings_on: ["CHANGELOG.md"]
    ]
  end
end
