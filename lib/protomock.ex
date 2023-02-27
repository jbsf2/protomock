defmodule ProtoMock do
  use GenServer

  defmodule VerificationError do
    defexception [:message]

    @spec exception([String.t()]) :: Exception.t()
    def exception(messages) do
      single_message = messages |> Enum.join("\n")
      %__MODULE__{message: single_message}
    end
  end

  defmodule UnexpectedCallError do
    defexception [:message]

    @spec exception({function(), non_neg_integer(), non_neg_integer()}) :: Exception.t()
    def exception({function, expected_count, actual_count}) do
      message = ProtoMock.exception_message(function, expected_count, actual_count)
      %__MODULE__{message: message}
    end
  end

  defmodule ImplAlreadyDefinedError do
    defexception [:message]

    def exception(protocol) do
      message = "ProtoMock already has an implementation defined for protocol #{protocol}"
      %__MODULE__{message: message}
    end
  end

  @typep quoted_expression :: {atom() | tuple(), keyword(), list() | atom()}

  @typep expectation :: %{
           mocked_function: function(),
           impl: function(),
           pending?: boolean()
         }

  @typep expected_count :: non_neg_integer() | :unlimited

  @typep invocation :: %{
           function: function(),
           args: [any()]
         }

  @typep state :: %{
           stubs: %{function() => function()},
           expectations: [expectation()],
           invocations: [invocation()]
         }

  defstruct [:pid]

  @opaque t :: %__MODULE__{
            pid: pid()
          }

  @spec defimpl(module()) :: :ok
  def defimpl(protocol) do
    Protocol.assert_protocol!(protocol)

    if impl_exists?(protocol), do: raise(ProtoMock.ImplAlreadyDefinedError, protocol)

    quoted =
      quote do
        defimpl unquote(protocol), for: unquote(ProtoMock) do
          (unquote_splicing(impl_functions(protocol)))
        end
      end

    {_term, _binding} = Code.eval_quoted(quoted)
    :ok
  end

  @spec new() :: t()
  def new() do
    state = %{stubs: %{}, expectations: [], invocations: []}
    {:ok, pid} = GenServer.start_link(__MODULE__, state)
    %__MODULE__{pid: pid}
  end

  @spec stub(t(), function(), function()) :: t()
  def stub(protomock, mocked_function, impl) do
    :ok = GenServer.call(protomock.pid, {:stub, mocked_function, impl})
    protomock
  end

  @spec expect(t(), function(), non_neg_integer(), function()) :: t()
  def expect(protomock, mocked_function, invocation_count \\ 1, impl) do
    :ok = GenServer.call(protomock.pid, {:expect, mocked_function, invocation_count, impl})
    protomock
  end

  @spec invoke(t(), function(), [any()]) :: t()
  def invoke(protomock, mocked_function, args) do
    reply = GenServer.call(protomock.pid, {:invoke, mocked_function, args})

    case reply do
      {UnexpectedCallError, args} -> raise UnexpectedCallError, args
      response -> response
    end
  end

  @spec verify!(t()) :: :ok
  def verify!(protomock) do
    state = GenServer.call(protomock.pid, :state)

    expected_counts = expected_counts(state)
    actual_counts = actual_counts(state.invocations)

    failure_messages =
      expected_counts
      |> Enum.reduce([], fn {function, expected_count}, acc ->
        actual_count = actual_counts |> Map.get(function, 0)

        case failed_expectations?(expected_count, actual_count) do
          true -> [exception_message(function, expected_count, actual_count) | acc]
          false -> acc
        end
      end)

    case failure_messages do
      [] -> :ok
      messages -> raise VerificationError, messages
    end
  end

  @impl true
  def init(init_arg) do
    {:ok, init_arg}
  end

  @impl true
  def handle_call({:stub, mocked_function, impl}, _from, state) do
    updated_stubs = state.stubs |> Map.put(mocked_function, impl)
    updated_state = %{state | stubs: updated_stubs}

    {:reply, :ok, updated_state}
  end

  @impl true
  def handle_call({:expect, mocked_function, invocation_count, impl}, _from, state) do
    new_expectations =
      for _ <- Range.new(1, invocation_count, 1) do
        %{
          mocked_function: mocked_function,
          impl: impl,
          pending?: true
        }
      end

    updated_expectations = state.expectations ++ new_expectations

    updated_state = %{state | expectations: updated_expectations}

    {:reply, :ok, updated_state}
  end

  @impl true
  def handle_call({:invoke, mocked_function, args}, _from, state) do
    invocation = %{function: mocked_function, args: args}
    updated_invocations = [invocation | state.invocations]

    expected_count = expected_count(state, mocked_function)
    actual_count = actual_count(updated_invocations, mocked_function)

    case exceeded_expectations?(expected_count, actual_count) do
      true ->
        updated_state = %{state | invocations: updated_invocations}
        error_args = {mocked_function, expected_count, actual_count}
        {:reply, {UnexpectedCallError, error_args}, updated_state}

      false ->
        {impl, updated_expectations} = next_impl(state, mocked_function)
        response = Kernel.apply(impl, args)

        updated_state = %{
          state
          | invocations: updated_invocations,
            expectations: updated_expectations
        }

        {:reply, response, updated_state}
    end
  end

  @impl true
  def handle_call(:state, _from, state) do
    {:reply, state, state}
  end

  # ----- private

  @spec next_impl(state(), function()) :: {function(), [expectation()]}
  defp next_impl(state, mocked_function) do
    expectations = state.expectations

    index =
      expectations
      |> Enum.find_index(fn expectation ->
        expectation.pending? && expectation.mocked_function == mocked_function
      end)

    case index do
      nil ->
        {stub_impl_for(state, mocked_function), expectations}

      index ->
        expectation = Enum.at(expectations, index)
        updated_expectations = expectations |> List.update_at(index, &%{&1 | pending?: false})
        {expectation.impl, updated_expectations}
    end
  end

  @spec stub_impl_for(state(), function()) :: function()
  defp stub_impl_for(state, mocked_function) do
    state.stubs |> Map.get(mocked_function)
  end

  @spec exceeded_expectations?(expected_count(), non_neg_integer()) :: boolean()
  defp exceeded_expectations?(expected_count, actual_count) do
    expected_count != :unlimited && expected_count < actual_count
  end

  @spec failed_expectations?(expected_count(), non_neg_integer()) :: boolean()
  defp failed_expectations?(expected_count, actual_count) do
    expected_count != :unlimited && actual_count < expected_count
  end

  @spec expected_count(state(), function) :: expected_count()
  defp expected_count(state, function) do
    expected_counts(state) |> Map.get(function, 0)
  end

  @spec expected_counts(state()) :: %{function() => expected_count()}
  defp expected_counts(state) do
    unlimiteds =
      state.stubs
      |> Enum.reduce(%{}, fn {mocked_function, _impl}, acc ->
        acc |> Map.put(mocked_function, :unlimited)
      end)

    state.expectations
    |> Enum.reduce(%{}, fn expectation, acc ->
      acc |> Map.update(expectation.mocked_function, 1, &(&1 + 1))
    end)
    |> Map.merge(unlimiteds, fn _, _, _ -> :unlimited end)
  end

  @spec actual_count([invocation()], function()) :: non_neg_integer()
  defp actual_count(invocations, function) do
    actual_counts(invocations) |> Map.get(function, 0)
  end

  @spec actual_counts([invocation()]) :: %{function() => non_neg_integer()}
  defp actual_counts(invocations) do
    invocations
    |> Enum.reduce(%{}, fn invocation, acc ->
      acc |> Map.update(invocation.function, 1, &(&1 + 1))
    end)
  end

  @spec times(non_neg_integer()) :: String.t()
  defp times(number) do
    case number do
      1 -> "once"
      2 -> "twice"
      n -> "#{n} times"
    end
  end

  @spec function_name(function()) :: String.t()
  defp function_name(function) do
    inspect(function) |> String.replace_leading("&", "")
  end

  def exception_message(function, expected_count, actual_count) do
    function_name = function_name(function)
    expected_times = times(expected_count)
    actual_times = times(actual_count)

    "expected #{function_name} to be called #{expected_times} but it was called #{actual_times}"
  end

  @spec impl_functions(module()) :: [quoted_expression()]
  defp impl_functions(protocol) do
    protocol.__protocol__(:functions)
    |> Enum.map(fn {function_name, arity} ->
      protomock = Macro.var(:protomock, __MODULE__)
      mocked_function = Function.capture(protocol, function_name, arity)
      args = Range.new(1, arity - 1, 1) |> Enum.map(&Macro.var(:"arg#{&1}", __MODULE__))

      quote do
        def unquote(function_name)(unquote(protomock), unquote_splicing(args)) do
          ProtoMock.invoke(
            protomock,
            unquote(mocked_function),
            unquote([protomock | args])
          )
        end
      end
    end)
  end

  @spec impl_exists?(module()) :: boolean()
  def impl_exists?(protocol) do
    impl = Module.concat(protocol, ProtoMock)
    module_exists?(impl) and impl.__impl__(:protocol) == protocol
  end

  @spec module_exists?(module()) :: boolean()
  def module_exists?(module), do: function_exported?(module, :__info__, 1)
end
