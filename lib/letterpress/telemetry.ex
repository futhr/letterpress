defmodule Letterpress.Telemetry do
  @moduledoc """
  Emits bounded discovery, compile, analyze, format, translation, and render telemetry.

  Metadata never includes source, output, values, variable names, or caller
  identifiers.
  """

  @operations ~w(discover analyze compile render format apply_translations)a

  @doc "Runs a public operation with start/stop/exception telemetry."
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
