defmodule Letterpress.Contract do
  @moduledoc """
  Loads the canonical contract shared by backend and browser packages.

  The file is generated from `contract/letterpress-v1.json` during the compiler
  build and included in the Hex archive.
  """

  @persistent_key {__MODULE__, :contract}

  @doc "Returns the decoded generated contract."
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
    contract = path |> File.read!() |> Jason.decode!()
    :persistent_term.put(@persistent_key, contract)
    contract
  end
end
