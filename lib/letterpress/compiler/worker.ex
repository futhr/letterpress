defmodule Letterpress.Compiler.Worker do
  @moduledoc """
  Owns one framed JSON connection to the bundled Node compiler.

  Requests are serialized per worker. Timeouts, malformed frames, mismatched
  IDs, and process exits fail queued callers and terminate the worker so its
  supervisor establishes a fresh protocol boundary.

  This is an implementation module. Applications supervise
  `Letterpress.Compiler.Supervisor` and use `Letterpress` or
  `Letterpress.Compiler`, rather than starting or calling workers directly.
  """

  use GenServer

  @typedoc false
  @type state :: %{
          port: port(),
          pending: nil | map(),
          queue: :queue.queue(),
          max_frame_bytes: pos_integer()
        }

  @default_pool Letterpress.Compiler.Pool

  @doc """
  Starts one compiler worker for the configured pool and index.

  Called by `Letterpress.Compiler.Supervisor`; it is not a host application
  integration point.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    index = Keyword.fetch!(opts, :index)
    pool = Keyword.get(opts, :pool, @default_pool)
    GenServer.start_link(__MODULE__, opts, name: via(pool, index))
  end

  @doc """
  Queues a request on a worker in the default compiler pool.

  Prefer `Letterpress.Compiler.request/3`, which selects an available worker and
  converts a missing pool into a tagged error.
  """
  @spec request(non_neg_integer(), atom(), map(), timeout()) :: {:ok, map()} | {:error, term()}
  def request(index, operation, payload, timeout) do
    request(@default_pool, index, operation, payload, timeout)
  end

  @doc false
  @spec request(atom(), non_neg_integer(), atom(), map(), timeout()) ::
          {:ok, map()} | {:error, term()}
  def request(pool, index, operation, payload, timeout) do
    GenServer.call(via(pool, index), {:request, operation, payload, timeout}, timeout + 1_000)
  rescue
    ArgumentError -> {:error, :compiler_unavailable}
  catch
    :exit, {:timeout, _} -> {:error, :compiler_timeout}
    :exit, _ -> {:error, :compiler_unavailable}
  end

  @impl GenServer
  def init(opts) do
    Process.flag(:trap_exit, true)

    with {:ok, port} <- open_port() do
      {:ok,
       %{
         port: port,
         pending: nil,
         queue: :queue.new(),
         max_frame_bytes: Keyword.get(opts, :max_frame_bytes, 2_000_000)
       }}
    end
  end

  @impl GenServer
  def handle_call({:request, operation, payload, timeout}, from, state) do
    request = %{from: from, operation: operation, payload: payload, timeout: timeout}
    {:noreply, enqueue_or_start(state, request)}
  end

  @impl GenServer
  def handle_info({port, {:data, frame}}, %{port: port, pending: pending} = state)
      when is_map(pending) do
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

  @impl GenServer
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
    |> then(&[{~c"LANG", ~c"C.UTF-8"} | &1])
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

  defp via(pool, index), do: {:via, Registry, {pool, index}}
end
