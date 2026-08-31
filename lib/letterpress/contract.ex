defmodule Letterpress.Contract do
  @moduledoc """
  Loads the generated contract shared by the backend and browser packages.

  The checked-in source lives at `contract/letterpress-v1.json`. Release tooling
  expands it into `priv/contract.json` and the TypeScript projection used by
  `@letterpress/language` and `@letterpress/svelte`. All projections carry the
  same contract version.

  The decoded map is cached in `:persistent_term` after its first read. Treat it
  as immutable application data.

  ## Example

      iex> contract = Letterpress.Contract.get()
      iex> {contract["contract_version"], Map.keys(contract["profiles"]) |> Enum.sort()}
      {1, ["email/mjml-liquid@1", "text/liquid@1"]}
  """

  @persistent_key {__MODULE__, :contract}

  @doc """
  Returns the decoded generated contract.

  The map includes profile definitions, schema vocabulary, diagnostics, limits,
  editor metadata, and pinned source versions. It is read from the installed
  application's `priv` directory and cached for later calls.
  """
  @spec get() :: map()
  def get do
    case :persistent_term.get(@persistent_key, :missing) do
      :missing -> load()
      contract -> contract
    end
  end

  @doc false
  @spec reset() :: :ok
  def reset do
    :persistent_term.erase(@persistent_key)
    :ok
  end

  defp load do
    path = Application.app_dir(:letterpress, "priv/contract.json")

    contract =
      path
      |> File.read!()
      |> Jason.decode!()

    :persistent_term.put(@persistent_key, contract)
    contract
  end
end
