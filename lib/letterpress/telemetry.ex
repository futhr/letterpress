defmodule Letterpress.Telemetry do
  @moduledoc """
  Documents telemetry emitted around public Letterpress operations.

  Discovery, analysis, compilation, formatting, translation, and rendering emit
  `:start` followed by either `:stop` or `:exception`. Metadata never includes
  template source, rendered output, values, variable names, or caller
  identifiers.

  ## Events

  All event names have the form `[:letterpress, operation, phase]`.

    * `:start` measures `:system_time` and includes `:profile` and `:operation`
    * `:stop` measures `:duration` and `:input_size`, and adds a low-cardinality
      `:result` classification
    * `:exception` measures `:duration` and `:input_size`, and adds `:kind` plus
      a redacted `:reason_class`

  Durations use native time units. Convert them with
  `System.convert_time_unit/3` in handlers or metric definitions.

  ## Attaching a handler

      :telemetry.attach(
        "my-app-letterpress-render",
        [:letterpress, :render, :stop],
        fn _event, measurements, metadata, _config ->
          MyApp.Metrics.record_render(measurements.duration, metadata.result)
        end,
        nil
      )
  """

  @operations ~w(discover analyze compile render format apply_translations localize)a

  @doc """
  Runs a supported operation with start, stop, and exception telemetry.

  This function preserves the wrapped function's return value and exception
  semantics. It is used by the public facade; consumers normally attach
  handlers instead of calling it directly.
  """
  @spec span(atom(), String.t(), non_neg_integer(), (-> term())) :: term()
  def span(operation, profile, input_size, fun) when operation in @operations do
    started = System.monotonic_time()
    metadata = %{profile: profile, operation: operation}

    :telemetry.execute(
      [:letterpress, operation, :start],
      %{system_time: System.system_time()},
      metadata
    )

    try do
      result = fun.()
      duration = System.monotonic_time() - started

      :telemetry.execute(
        [:letterpress, operation, :stop],
        %{duration: duration, input_size: input_size},
        Map.put(metadata, :result, result_class(result))
      )

      result
    catch
      kind, reason ->
        duration = System.monotonic_time() - started

        :telemetry.execute(
          [:letterpress, operation, :exception],
          %{duration: duration, input_size: input_size},
          Map.merge(metadata, %{kind: kind, reason_class: reason_class(reason)})
        )

        :erlang.raise(kind, reason, __STACKTRACE__)
    end
  end

  defp result_class({:ok, _, _}), do: :ok
  defp result_class({:ok, _}), do: :ok
  defp result_class({:error, _}), do: :error
  defp result_class(_), do: :other

  defp reason_class(reason) when is_atom(reason), do: :atom
  defp reason_class(reason) when is_exception(reason), do: reason.__struct__
  defp reason_class(_), do: :unknown
end
