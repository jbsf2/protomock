# Agent for storing / retrieving global configuration.
# Right now there is only one piece of configuration: check_runtime_types.
defmodule ProtoMock.ConfigAgent do
  @moduledoc false

  @spec ensure_started() :: :ok
  def ensure_started() do
    if Process.whereis(__MODULE__) == nil do
      # If tests are run in parallel, it's possible that multiple test
      # processes might try to start the agent at the same time.
      # Only one will succeed. We choose to live with the (harmless) race condition
      # in favor of developer ergonomics, in that developers don't have
      # to explicitly start any global ProtoMock processes.
      Agent.start_link(fn -> %{check_runtime_types: false} end, name: __MODULE__)
    end

    :ok
  end

  @spec set(atom(), any()) :: :ok
  def set(key, value) do
    Agent.update(__MODULE__, fn config ->
      Map.put(config, key, value)
    end)
  end

  @spec get(atom()) :: any()
  def get(key) do
    Agent.get(__MODULE__, fn config ->
      Map.get(config, key)
    end)
  end
end
