defmodule Letterpress.TelemetryTest do
  @moduledoc false

  use ExUnit.Case, async: false

  import Letterpress.Test.Fixtures

  test "telemetry is bounded and excludes source and values" do
    parent = self()
    handler = "letterpress-test-#{System.unique_integer([:positive])}"
    events = [[:letterpress, :compile, :start], [:letterpress, :compile, :stop]]

    :ok =
      :telemetry.attach_many(
        handler,
        events,
        &__MODULE__.handle_event/4,
        parent
      )

    on_exit(fn -> :telemetry.detach(handler) end)

    assert {:ok, _, _} = Letterpress.compile("text/liquid@1", text_source(), text_schema())
    assert_receive {[:letterpress, :compile, :start], _, start_metadata}
    assert_receive {[:letterpress, :compile, :stop], _, stop_metadata}

    for metadata <- [start_metadata, stop_metadata] do
      refute Map.has_key?(metadata, :source)
      refute Map.has_key?(metadata, :values)
      assert metadata.profile == "text/liquid@1"
    end
  end

  test "exception telemetry exposes only bounded reason classes" do
    parent = self()
    handler = "letterpress-exception-test-#{System.unique_integer([:positive])}"

    :ok =
      :telemetry.attach(
        handler,
        [:letterpress, :render, :exception],
        &__MODULE__.handle_event/4,
        parent
      )

    on_exit(fn -> :telemetry.detach(handler) end)

    assert_raise RuntimeError, "private failure", fn ->
      Letterpress.Telemetry.span(:render, "text/liquid@1", 12, fn ->
        raise "private failure"
      end)
    end

    assert_receive {[:letterpress, :render, :exception], measurements, metadata}
    assert is_integer(measurements.duration)
    assert metadata.reason_class == RuntimeError
    refute Map.has_key?(metadata, :reason)
  end

  test "telemetry classifies non-tuple results without attaching their content" do
    parent = self()
    handler = "letterpress-result-test-#{System.unique_integer([:positive])}"

    :ok =
      :telemetry.attach(
        handler,
        [:letterpress, :format, :stop],
        &__MODULE__.handle_event/4,
        parent
      )

    on_exit(fn -> :telemetry.detach(handler) end)

    assert :private_value =
             Letterpress.Telemetry.span(:format, "text/liquid@1", 0, fn -> :private_value end)

    assert_receive {[:letterpress, :format, :stop], _, %{result: :other} = metadata}
    refute Map.has_key?(metadata, :value)
  end

  test "non-exception failures collapse into bounded telemetry classes" do
    parent = self()
    handler = "letterpress-reason-test-#{System.unique_integer([:positive])}"

    :ok =
      :telemetry.attach(
        handler,
        [:letterpress, :analyze, :exception],
        &__MODULE__.handle_event/4,
        parent
      )

    on_exit(fn -> :telemetry.detach(handler) end)

    assert catch_throw(
             Letterpress.Telemetry.span(:analyze, "text/liquid@1", 0, fn ->
               throw(:private_reason)
             end)
           ) == :private_reason

    assert_receive {[:letterpress, :analyze, :exception], _, %{reason_class: :atom}}

    assert catch_exit(
             Letterpress.Telemetry.span(:analyze, "text/liquid@1", 0, fn ->
               exit({:private, 42})
             end)
           ) == {:private, 42}

    assert_receive {[:letterpress, :analyze, :exception], _, %{reason_class: :unknown}}
  end

  def handle_event(event, measurements, metadata, recipient) do
    send(recipient, {event, measurements, metadata})
  end
end
