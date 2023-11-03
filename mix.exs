defmodule ProtoMock.MixProject do
  use Mix.Project

  @version "0.5.0"
  @github_page "https://github.com/jbsf2/protomock"

  def project do
    [
      app: :protomock,
      version: @version,
      elixir: "~> 1.14",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      # elixirc_options: [warnings_as_errors: true],
      elixirc_paths: elixirc_paths(Mix.env()),
      consolidate_protocols: Mix.env() != :test,

      # Docs
      name: "ProtoMock",
      homepage_url: @github_page,
      source_url: "https://github.com/jbsf2/protomock",
      docs: docs(),
      package: package()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # ensure test/support is compiled
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:dialyxir, "~> 1.2", only: :dev, runtime: false},
      {:ex_doc, "~> 0.30.3", only: :dev, runtime: false}
    ]
  end

  defp docs do
    [
      api_reference: false,
      authors: ["JB Steadman"],
      canonical: "http://hexdocs.pm/protomock",
      extras: ["README.md"],
      main: "ProtoMock",
      source_ref: "v#{@version}"
    ]
  end

  defp package do
    [
      files: ~w(mix.exs README.md lib),
      licenses: ["MIT"],
      links: %{
        "GitHub" => @github_page,
        "marcdel.com" => "https://www.marcdel.com",
        "OpenTelemetry Erlang SDK" => "https://github.com/open-telemetry/opentelemetry-erlang"
      },
      maintainers: ["JB Steadman"]
    ]
  end
end
