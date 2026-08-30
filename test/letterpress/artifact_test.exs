defmodule Letterpress.ArtifactTest do
  @moduledoc false

  use ExUnit.Case, async: false

  import Letterpress.Test.Fixtures

  alias Letterpress.{Artifact, CanonicalJSON}

  setup do
    {:ok, artifact, _} = Letterpress.compile("text/liquid@1", text_source(), text_schema())
    %{artifact: artifact}
  end

  test "canonical encode/decode round trips and verifies content", %{artifact: artifact} do
    assert {:ok, json} = Artifact.encode(artifact)
    assert {:ok, decoded} = Artifact.decode(json)
    assert decoded == artifact
  end

  test "tampering and unknown versions fail closed", %{artifact: artifact} do
    map = Artifact.to_map(artifact)
    assert {:error, :artifact_hash_mismatch} = Artifact.decode(Map.put(map, "text", "changed"))

    assert {:error, :unsupported_artifact_version} =
             Artifact.decode(Map.put(map, "artifact_version", 2))
  end

  test "a recomputed checksum cannot turn untrusted Liquid into an artifact", %{
    artifact: artifact
  } do
    forged =
      artifact
      |> Artifact.to_map()
      |> Map.put("text", "Hello {{ name }}")
      |> rehash()

    assert {:error, :invalid_artifact_context_filter} = Artifact.decode(forged)
  end

  test "rejects unknown fields and malformed compiler or variable metadata", %{
    artifact: artifact
  } do
    map = Artifact.to_map(artifact)

    assert {:error, :invalid_artifact} =
             map |> Map.put("unexpected", true) |> rehash() |> Artifact.decode()

    assert {:error, :invalid_artifact_compiler} =
             map
             |> put_in(["compiler", "node"], "latest")
             |> rehash()
             |> Artifact.decode()

    assert {:error, :invalid_artifact_variables} =
             map
             |> update_in(["variables"], fn [first | rest] ->
               [Map.put(first, "default", 42) | rest]
             end)
             |> rehash()
             |> Artifact.decode()
  end

  test "rejects malformed JSON, hashes, profiles, channels, and metadata", %{artifact: artifact} do
    map = Artifact.to_map(artifact)

    assert {:error, %Jason.DecodeError{}} = Artifact.decode("not json")
    assert {:error, :invalid_artifact} = Artifact.decode([])

    cases = [
      {Map.put(map, "profile", "unknown@1"), :invalid_artifact_profile},
      {Map.put(map, "source_sha256", "short"), :invalid_artifact_hash},
      {Map.put(map, "text", nil), :invalid_artifact_channels},
      {Map.put(map, "translation_units", [%{}]), :invalid_artifact_translation_units},
      {Map.put(map, "source_map", %{"bad" => %{}}), :invalid_artifact_source_map},
      {Map.put(map, "lint", [%{"severity" => "error"}]), :invalid_artifact_lint},
      {put_in(map, ["compiler", "extra"], "1.0.0"), :invalid_artifact_compiler}
    ]

    for {candidate, reason} <- cases do
      assert {:error, ^reason} = candidate |> rehash() |> Artifact.decode()
    end
  end

  test "encoding rechecks the stored content hash", %{artifact: artifact} do
    assert {:error, :artifact_hash_mismatch} =
             artifact
             |> Map.put(:content_sha256, String.duplicate("0", 64))
             |> Artifact.encode()
  end

  defp rehash(map) do
    Map.put(map, "content_sha256", map |> Map.delete("content_sha256") |> CanonicalJSON.hash())
  end
end
