defmodule Letterpress.Profile do
  @moduledoc """
  Resolves versioned template profiles from the generated contract.

  A profile fixes the source language, output channels, allowed elements and
  attributes, formatting rules, and compiler behavior. Existing identifiers
  never change meaning; incompatible behavior requires a new identifier.

  Unsupported or malformed identifiers fail before compiler work begins.

  ## Example

      iex> Letterpress.Profile.all()
      ["email/mjml-liquid@1", "text/liquid@1"]
  """

  alias Letterpress.{Contract, Diagnostic}

  @doc "Returns the supported profile identifiers in lexical order."
  @spec all() :: [String.t()]
  def all do
    Contract.get()
    |> Map.fetch!("profiles")
    |> Map.keys()
    |> Enum.sort()
  end

  @doc """
  Validates a public profile identifier.

  ## Examples

      iex> Letterpress.Profile.validate("text/liquid@1")
      :ok

      iex> {:error, [diagnostic]} = Letterpress.Profile.validate("unknown")
      iex> diagnostic.code
      "LP_PROFILE_UNKNOWN"
  """
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

  @doc """
  Fetches the generated metadata for a profile.

  Returns `:error` when the identifier is not present in the current contract.

  ## Example

      iex> {:ok, metadata} = Letterpress.Profile.fetch("email/mjml-liquid@1")
      iex> metadata["kind"]
      "email"
  """
  @spec fetch(String.t()) :: {:ok, map()} | :error
  def fetch(profile), do: Map.fetch(Contract.get()["profiles"], profile)
end
