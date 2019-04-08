defmodule Sweetroll2.MixProject do
  use Mix.Project

  def project do
    [
      app: :sweetroll2,
      version: "0.1.0",
      elixir: "~> 1.7",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger, :httpotion],
      mod: {Sweetroll2.Application, []}
    ]
  end

  defp deps do
    [
      # Data
      {:jason, "~> 1.1"},
      {:earmark, "~> 1.3"},
      {:phoenix_html, "~> 2.13"},
      {:taggart, "~> 0.1.5"},
      # {:microformats2, "~> 0.2"},
      {:floki, git: "https://github.com/philss/floki", override: true},
      {:html5ever, "~> 0.7.0"},
      {:microformats2, git: "https://github.com/ckruse/microformats2-elixir"},

      # DB
      {:ecto_sql, "~> 3.0"},
      {:ecto_job, "~> 2.0"},
      {:postgrex, ">= 0.0.0"},

      # HTTP
      {:httpotion, "~> 3.1"},
      {:plug_cowboy, "~> 2.0"},
      {:sse, "~> 0.4"},
      {:event_bus, ">= 1.6.0"}
    ]
  end
end
