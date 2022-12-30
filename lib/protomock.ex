defmodule ProtoMock do

  use GenServer

  defmodule VerificationError do
    defexception [:message]
  end

  defmodule UnexpectedCallError do

    defexception [:message]

    def exception({function, expected_count, actual_count}) do
      function_name = ProtoMock.function_name(function)
      expected_times = ProtoMock.times(expected_count)
      actual_times = ProtoMock.times(actual_count)

      message = "expected #{function_name} to be called #{expected_times} but it was called #{actual_times}"
      %__MODULE__{message: message}
    end
  end

  @type expectation :: %{
    mocked_function: function(),
    invocation_count: non_neg_integer(),
    impl: function()
  }

  @type invocation :: %{
    function: function(),
    args: [any()]
  }

  @type state :: %{
    expectations: [expectation()],
    invocations: [invocation()]
  }

  defstruct [:name]
  @type t :: %__MODULE__{
    name: atom()
  }

  @spec new() :: t()
  def new() do
    name = random_genserver_name()
    state = %{expectations: [], invocations: []}
    {:ok, _pid} = GenServer.start_link(__MODULE__, state, name: name)
    %__MODULE__{name: name}
  end

  @spec expect(t(), function(), non_neg_integer(), function()) :: t()
  def expect(protomock, mocked_function, invocation_count \\ 1, impl) do
    :ok = GenServer.call(protomock.name, {:expect, mocked_function, invocation_count, impl})
    protomock
  end

  @spec invoke(t(), function(), [any()]) :: t()
  def invoke(protomock, mocked_function, args \\ []) do
    reply = GenServer.call(protomock.name, {:invoke, mocked_function, [protomock | args]})
    case reply do
      {UnexpectedCallError, args} -> raise UnexpectedCallError, args
      response -> response
    end
  end

  @spec verify!(t()) :: t()
  def verify!(protomock) do
    state = GenServer.call(protomock.name, :state)
    expectations = state.expectations
    invocations = state.invocations

    if (length(expectations) != length(invocations)) do
      message = "expected #{length(expectations)} function calls, but got #{length(invocations)}"
      raise VerificationError, message: message
    end

    :ok
  end

  @impl true
  def init(init_arg) do
    {:ok, init_arg}
  end

  @impl true
  def handle_call({:expect, mocked_function, invocation_count, impl}, _from, state) do
    new_expectation = %{
      mocked_function: mocked_function,
      invocation_count: invocation_count,
      impl: impl
    }
    updated_expectations = state.expectations |> List.insert_at(-1, new_expectation)

    updated_state = %{state | expectations: updated_expectations}

    {:reply, :ok, updated_state}
  end

  @impl true
  def handle_call({:invoke, mocked_function, args}, _from, state) do
    expectation = state.expectations |> Enum.at(length(state.invocations))

    invocation = %{function: mocked_function, args: args}
    updated_invocations = [invocation | state.invocations]

    expected_count = expected_count(state.expectations, mocked_function)
    actual_count = actual_count(updated_invocations, mocked_function)

    case actual_count > expected_count do
      true ->
        {:reply, {UnexpectedCallError, {mocked_function, expected_count, actual_count}}, state}

      false ->
        response = Kernel.apply(expectation.impl, args)
        updated_state = %{state | invocations: updated_invocations}
        {:reply, response, updated_state}
    end
  end

  @impl true
  def handle_call(:state, _from, state) do
    {:reply, state, state}
  end

  # @impl true
  # def terminate(reason, _state) do
  #   IO.puts("reason: #{inspect(reason)}")
  # end

  @impl true
  def handle_info({:link, link}, state) do
    IO.puts("link")
    Process.link(link)
    {:noreply, state}
  end

  def handle_info(message, state) do
    IO.puts("handle_info message: #{inspect(message)}")
    {:noreply, state}
  end

  # ----- private

  defp random_genserver_name() do
    random = :rand.uniform(10_000_000_000)
    random |> Integer.to_string() |> String.to_atom()
  end

  @spec expected_count([expectation()], function) :: non_neg_integer()
  defp expected_count(expectations, function) do
    expectations
    |> Enum.filter(&(&1.mocked_function == function))
    |> expected_counts()
    |> Map.get(function)
  end

  @spec expected_counts([expectation()]) :: %{function() => non_neg_integer()}
  defp expected_counts(expectations) do
    expectations
    |> Enum.reduce(%{}, fn expectation, acc ->
      mocked_function = expectation.mocked_function
      existing_count = acc |> Map.get(mocked_function, 0)
      updated_count = existing_count + expectation.invocation_count
      acc |> Map.put(mocked_function, updated_count)
    end)
  end

  @spec actual_count([invocation()], function) :: non_neg_integer()
  defp actual_count(invocations, function) do
    invocations
    |> Enum.filter(&(&1.function == function))
    |> actual_counts()
    |> Map.get(function)
  end

  @spec actual_counts([invocation()]) :: %{function() => non_neg_integer()}
  defp actual_counts(invocations) do
    invocations
    |> Enum.reduce(%{}, fn invocation, acc ->
      function = invocation.function
      existing_count = acc |> Map.get(function, 0)
      updated_count = existing_count + 1
      acc |> Map.put(function, updated_count)
    end)
  end

  @spec times(non_neg_integer()) :: String.t()
  def times(number) do
    case number do
      1 -> "once"
      2 -> "twice"
      n -> "#{n} times"
    end
  end

  @spec function_name(function()) :: String.t()
  def function_name(function) do
    inspect(function) |> String.replace_leading("&", "")
  end
end
