defmodule Letterpress.Profile do
  @moduledoc """
  Resolves immutable profile identifiers from the generated contract.

  Existing identifiers never change meaning. Unsupported identifiers fail
  before compiler or renderer work begins.
  """

  alias Letterpress.{Contract, Diagnostic}

  @doc "Returns supported profile identifiers in lexical order."
  @spec all() :: [String.t()]
  def all do
    Contract.get()
    |> Map.fetch!("profiles")
    |> Map.keys()
    |> Enum.sort()
  end

  @doc "Validates a public profile identifier."
  @spec validate(term()) :: :ok | {:error, [Diagnostic.t()]}
  def validate(profile) when is_binary(profile) do
    if profile in all() do
      :ok
    else
      {:error, [Diagnostic.simple("LP_PROFILE_UNKNOWN", "Unsupported profile #{profile}")]}
    end
  end

  def validate(_),
    do: {:error, [Diagnostic.simple("LP_PROFILE_INVALID", "Profile must be a string")]}

  @doc "Returns the profile metadata or an error."
  @spec fetch(String.t()) :: {:ok, map()} | :error
  def fetch(profile), do: Map.fetch(Contract.get()["profiles"], profile)
end
