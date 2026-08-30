defmodule Letterpress.Compiler.Worker do
  @moduledoc """
  Owns one framed JSON connection to the bundled Node compiler.

  Requests are serialized per worker. Timeouts, malformed frames, mismatched
  IDs, and process exits fail queued callers and terminate the worker so its
  supervisor establishes a fresh protocol boundary.
  """

  use GenServer

  @type state :: %{
          port: port(),
          pending: nil | map(),
          queue: :queue.queue(),
          max_frame_bytes: pos_integer()
        }

  @doc "Starts one compiler worker at `:index`."
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    index = Keyword.fetch!(opts, :index)
    GenServer.start_link(__MODULE__, opts, name: via(index))
  end

  @doc "Queues a request on the selected worker."
  @spec request(non_neg_integer(), atom(), map(), timeout()) :: {:ok, map()} | {:error, term()}
  def request(index, operation, payload, timeout) do
    GenServer.call(via(index), {:request, operation, payload, timeout}, timeout + 1_000)
  rescue
    ArgumentError -> {:error, :compiler_unavailable}
  catch
    :exit, {:timeout, _} -> {:error, :compiler_timeout}
    :exit, _ -> {:error, :compiler_unavailable}
  end

  @impl true
  def init(_) do
    Process.flag(:trap_exit, true)

    with {:ok, port} <- open_port() do
      {:ok,
       %{
         port: port,
         pending: nil,
         queue: :queue.new(),
         max_frame_bytes: Application.get_env(:letterpress, :compiler_max_frame_bytes, 2_000_000)
       }}
    end
  end

  @impl true
  def handle_call({:request, operation, payload, timeout}, from, state) do
    request = %{from: from, operation: operation, payload: payload, timeout: timeout}
    {:noreply, enqueue_or_start(state, request)}
  end

  @impl true
  def handle_info({port, {:data, frame}}, %{port: port, pending: pending} = state)
      when not is_nil(pending) do
    with true <- byte_size(frame) <= state.max_frame_bytes,
         {:ok, response} <- Jason.decode(frame),
         true <- response["id"] == pending.id do
      _ = Process.cancel_timer(pending.timer)
      GenServer.reply(pending.from, response_result(response))
      {:noreply, start_next(%{state | pending: nil})}
    else
      _ -> stop_protocol(state, :compiler_protocol_error)
    end
  end

  def handle_info({:compiler_timeout, id}, %{pending: %{id: id} = pending} = state) do
    GenServer.reply(pending.from, {:error, :compiler_timeout})
    stop_protocol(%{state | pending: nil}, :compiler_timeout)
  end

  def handle_info({port, {:exit_status, _}}, %{port: port} = state) do
    stop_protocol(state, :compiler_unavailable)
  end

  def handle_info({:EXIT, port, _}, %{port: port} = state) do
    stop_protocol(state, :compiler_unavailable)
  end

  def handle_info(_, state), do: {:noreply, state}

  @impl true
  def terminate(_, %{port: port}) do
    if Port.info(port), do: Port.close(port)
    :ok
  catch
    :error, :badarg -> :ok
  end

  defp open_port do
    with node when is_binary(node) <- System.find_executable("node"),
         priv_dir <- resolved_priv_dir(),
         worker <- Path.join(priv_dir, "compiler/worker.mjs"),
         true <- File.regular?(worker) do
      args = ["--permission", "--allow-fs-read=#{priv_dir}", worker]

      {:ok,
       Port.open(
         {:spawn_executable, node},
         [
           :binary,
           :exit_status,
           :use_stdio,
           {:packet, 4},
           {:args, args},
           {:cd, Path.dirname(worker)},
           {:env, sanitized_environment()}
         ]
       )}
    else
      _ -> {:stop, :compiler_unavailable}
    end
  end

  defp resolved_priv_dir do
    priv_dir = Application.app_dir(:letterpress, "priv")

    case File.read_link(priv_dir) do
      {:ok, target} -> Path.expand(target, Path.dirname(priv_dir))
      {:error, _} -> priv_dir
    end
  end

  defp sanitized_environment do
    System.get_env()
    |> Map.keys()
    |> Enum.reject(&(&1 == "LANG"))
    |> Enum.map(&{String.to_charlist(&1), false})
    |> then(&(&1 ++ [{~c"LANG", ~c"C.UTF-8"}]))
  end

  defp enqueue_or_start(%{pending: nil} = state, request), do: start_request(state, request)

  defp enqueue_or_start(state, request) do
    %{state | queue: :queue.in(request, state.queue)}
  end

  defp start_request(state, request) do
    id = Base.url_encode64(:crypto.strong_rand_bytes(12), padding: false)

    frame =
      Jason.encode!(%{
        "id" => id,
        "operation" => Atom.to_string(request.operation),
        "payload" => request.payload
      })

    if byte_size(frame) > state.max_frame_bytes do
      GenServer.reply(request.from, {:error, :compiler_frame_too_large})
      start_next(state)
    else
      true = Port.command(state.port, frame)
      timer = Process.send_after(self(), {:compiler_timeout, id}, request.timeout)
      %{state | pending: Map.merge(request, %{id: id, timer: timer})}
    end
  end

  defp start_next(state) do
    case :queue.out(state.queue) do
      {{:value, request}, queue} -> start_request(%{state | queue: queue}, request)
      {:empty, _} -> state
    end
  end

  defp response_result(%{"ok" => true, "result" => result}), do: {:ok, result}
  defp response_result(%{"ok" => false, "error" => error}), do: {:error, {:compiler_error, error}}
  defp response_result(_), do: {:error, :compiler_protocol_error}

  defp stop_protocol(state, reason) do
    fail_waiters(state, reason)
    {:stop, reason, %{state | pending: nil, queue: :queue.new()}}
  end

  defp fail_waiters(%{pending: pending, queue: queue}, reason) do
    if pending do
      _ = Process.cancel_timer(pending.timer)
      GenServer.reply(pending.from, {:error, reason})
    end

    queue
    |> :queue.to_list()
    |> Enum.each(&GenServer.reply(&1.from, {:error, reason}))
  end

  defp via(index), do: {:via, Registry, {Letterpress.Compiler.Registry, index}}
end
