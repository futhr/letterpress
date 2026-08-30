artifact =
  case System.argv() do
    [path] -> Path.expand(path)
    _ -> raise "usage: elixir scripts/publish-hex.exs PATH_TO_TARBALL"
  end

api_key = System.fetch_env!("HEX_API_KEY")

hex_ebin =
  System.user_home!()
  |> Path.join(".mix/archives/hex-*/hex-*/ebin")
  |> Path.wildcard()
  |> Enum.sort(:desc)
  |> List.first()

if is_nil(hex_ebin), do: raise("Hex archive not found; run `mix local.hex --force`")
true = Code.prepend_path(hex_ebin)
{:ok, _} = Application.ensure_all_started(:ssl)
{:ok, _} = Application.ensure_all_started(:inets)

config =
  :mix_hex_core.default_config()
  |> Map.put(:api_key, api_key)
  |> Map.put(:http_user_agent_fragment, "letterpress-release")

case :mix_hex_api_release.publish(config, File.read!(artifact)) do
  {:ok, {status, _, _}} when status in 200..299 ->
    IO.puts("Published exact Hex artifact #{Path.basename(artifact)}")

  {:ok, {status, _, body}} ->
    raise "Hex publish failed with HTTP #{status}: #{inspect(body)}"

  {:error, reason} ->
    raise "Hex publish failed: #{inspect(reason)}"
end
