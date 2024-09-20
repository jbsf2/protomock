defmodule ProtoMock do
  @external_resource "README.md"

  @moduledoc "README.md"
             |> File.read!()
             |> String.split("<!-- MDOC -->")
             |> Enum.filter(&(&1 =~ ~r{<!\-\-\ INCLUDE\ \-\->}))
             |> Enum.join("\n")
             # compensate for anchor id differences between ExDoc and GitHub
             |> (&Regex.replace(~r{\(\#\K(?=[a-z][a-z0-9-]+\))}, &1, "module-")).()

  use GenServer

  alias ProtoMock.ConfigAgent
  alias ProtoMock.ImplCreator
  alias ProtoMock.RuntimeTypeChecker

  defmodule VerificationError do
    @moduledoc """
    Error raised by `ProtoMock.verify!/1` when expectations set via `ProtoMock.expect/4`
    have not been satisfied.
    """
    defexception [:message]

    @spec exception([String.t()]) :: Exception.t()
    def exception(messages) do
      single_message = messages |> Enum.join("\n")
      %__MODULE__{message: single_message}
    end
  end

  defmodule UnexpectedCallError do
    @moduledoc """
    Error raised when a protocol function is invoked more times than expected.
    """
    defexception [:message]

    @spec exception({function(), non_neg_integer(), non_neg_integer()}) :: Exception.t()
    def exception({function, expected_count, actual_count}) do
      message = ProtoMock.exception_message(function, expected_count, actual_count)
      %__MODULE__{message: message}
    end
  end

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
           mocked_protocol: module(),
           delegate: struct(),
           stubs: %{function() => function()},
           expectations: [expectation()],
           invocations: [invocation()],
           check_runtime_types: boolean()
         }

  defstruct [:pid]

  @opaque t :: %__MODULE__{
            pid: pid()
          }

  # child_spec/1 is injected by GenServer. We override it and set @doc false
  # so that it doesn't appear in docs.
  @doc false
  def child_spec(_), do: nil

  @doc false
  @spec new() :: t()
  def new() do
    new(nil, nil, [])
  end

  @doc """
  Creates a new instance of `ProtoMock` that mocks the given `protocol`.

  After creating a new `ProtoMock`, tests can add expectations and stubs to the instance
  using `expect/4` and `stub/3`. With expectations and stubs in place, the `ProtoMock`
  instance can be provided to the code under test, and used by the code under test
  where it expects an implementation of `protocol`.

  If ProtoMock does not yet implement `protocol`, `new/1` will generate an implementation.

  Subsequent calls to `expect/4` and `stub/3` will verify that their mocked functions are
  member functions of `protocol`.

  The `ProtoMock` module is a GenServer. `new/1` starts a new instance of the GenServer
  that is linked to the calling process, typically an ExUnit test pid. When the test pid
  exits, any child `ProtoMock` GenServers also exit.
  """
  @spec new(module()) :: t()
  def new(protocol) do
    new(protocol, nil, [])
  end

  @doc """
  Creates a new instance of `ProtoMock` that mocks the given `protocol` and delegates
  non-customized function calls to `delegate`.

  `delegate` must be a data structure that implements `protocol`. By default, the `ProtoMock`
  instance returned by `new/2` will delegate any function calls to `delegate`. Delegation
  can be "overridden" on a per-function basis by calling `expect/4` or `stub/3` for any
  function of interest.

  For example, consider the following `Calculator` protocol:

      defprotocol Calculator do
        def add(calculator, x, y)

        def mult(calculator, x, y)

        def sqrt(calulator, x)
      end

  And suppose we have an implentation called `RealCalculator` that implements the protocol
  functions in the expected manner. We can create a `ProtoMock` instance stubs out one
  `Calculator` function while delegating the others to an instance of `RealCalculator`:

      protomock =
        ProtoMock.new(Calculator, RealCalculator.new())
        |> ProtoMock.stub(&Calculator.add/3, fn _calculator, _x, _y -> :overridden end)

      Calculator.add(protomock, 1, 2)  # => :overridden
      Calculator.mult(protomock, 1, 2) # => 2
      Calculator.sqrt(protomock, 4)    # => 2.0

  When a function is overriden using `expect/4`, ProtoMock will raise an error if the
  function is called more times than expected. If instead it's desired that the function
  should be delegated after expectations are met, `stub/3` can be used in conjunction
  with `expect/4` to establish the delegation:

      real_calculator = RealCalculator.new()

      protomock =
        ProtoMock.new(Calculator, real_calculator)
        |> ProtoMock.expect(&Calculator.add/3, 1, fn _calculator, _x, _y -> :overridden end)
        |> ProtoMock.stub(&Calculator.add/3, fn _calculator, x, y ->
          Calculator.add(real_calculator, x, y)
        end)

      Calculator.add(protomock, 1, 2)  # => :overridden
      Calculator.add(protomock, 1, 2)  # => 3
  """
  @spec new(module(), struct()) :: t()
  def new(protocol, delegate) do

    if delegate == nil do
      raise ArgumentError, "delegate must not be nil"
    end

    new(protocol, delegate, [])
  end

  @doc false
  # use of opts is "private" and intended only for ProtoMockTest
  @spec new(module(), struct() | nil,  keyword()) :: t()
  def new(protocol, delegate, opts) do
    :ok = ensure_protomock_started()

    if protocol != nil, do: :ok = create_impl(protocol)

    if delegate != nil && protocol.impl_for(delegate) == nil do
      raise ArgumentError, """
      The provided delegate must implement the #{inspect(protocol)} protocol, but it does not.
      """
    end

    state = %{
      mocked_protocol: protocol,
      delegate: delegate,
      stubs: %{},
      expectations: [],
      invocations: [],
      check_runtime_types: check_runtime_types?(opts)
    }

    {:ok, pid} = GenServer.start_link(__MODULE__, state)
    %__MODULE__{pid: pid}
  end

  # @doc """
  # Enables runtime type checking on a system-wide basis.

  # If type checking is desired, `enable_type_checking/0` is meant to
  # be invoked within `test_helper.exs` or equivalent, like this:

  #       ProtoMock.enable_type_checking()

  # Runtime type checking ensures that when a function is invoked on a mocked
  # protocol, the arguments passed to the function, and the value returned from
  # the mock implementation, both satisfy the typespec of the mocked function.
  # (Dialyzer will validate argument types within .ex files, but not .exs files)

  # Validating the type of return values can ensure that the production code using
  # your protocol will properly handle "real-life" return types. It identifies API
  # contract errors in your mock implementations and prevents them from leaking into
  # the production code that uses your protocol.

  # Typespecs are optional on protocol functions. Runtime type checking cannot
  # identify typing errors for mocked functions that do not have typespecs.

  # Runtime type checking relies on an undocumented module in core Elixir:
  # `Code.Typespec`. If `Code.Typespec` is ever removed or changed, runtime type
  # checking may be impacted.

  # ProtoMock's implementation of type checking relies heavily on code from
  # [Hammox](https://hexdocs.pm/hammox/Hammox.html).
  # """
  @doc false
  @spec enable_type_checking() :: :ok
  def enable_type_checking() do
    :ok = ensure_protomock_started()
    ConfigAgent.set(:check_runtime_types, true)
  end

  @doc """
  Allows `mocked_function` to be dispatched to `protomock` and proxied to `impl`.

  When `mocked_function` is dispatched, the `impl` function will be invoked, using the
  arguments passed to `mocked_function` (except for the first arg - see next paragraph).
  The value returned from `impl` will be returned from `mocked_function`.

  The `impl` function must have an arity that is one less than the arity of
  `mocked_function`. Because `mocked_function` is a protocol function, its first
  argument is the data structure that implements the protocol, which in this case is
  `protomock`. The `impl` function has no need for this data structure, so it is omitted
  from the `impl` argument list.

  Unlike expectations, stubs are never verified.

  If expectations and stubs are defined for the same `mocked_function`, the stub is
  invoked only after all expectations are fulfilled.

  `stub/3` will raise an `ArgumentError` if `mocked_function` is not a member function
  of the protocol mocked by `protomock`, as indicated via `new/1`.

  ## Example

  To allow `WeatherAPI.temperature/2` to be dispatched to a `ProtoMock` instance any
  number of times:

      protomock =
        ProtoMock.new(WeatherAPI)
        |> ProtoMock.stub(&WeatherAPI.temperature/2, fn _lat_long -> {:ok, 30} end)

  `stub/3` will overwrite any previous calls to `stub/3`.
  """
  @spec stub(t(), function(), function()) :: t()
  def stub(protomock, mocked_function, impl) do
    assert_protomock_implements!(mocked_function)
    validate_arity!(mocked_function, impl)

    reply = GenServer.call(protomock.pid, {:stub, mocked_function, impl})

    case reply do
      :ok -> protomock
      %ArgumentError{message: msg} -> raise ArgumentError.exception(msg)
    end
  end

  @doc """
  Expects `mocked_function` to be dispatched to `protomock` `invocation_count` times.

  When `mocked_function` is dispatched, the `impl` function will be invoked, using the
  arguments passed to `mocked_function` (except for the first arg - see next paragraph).
  The value returned from `impl` will be returned from `mocked_function`.

  The `impl` function must have an arity that is one less than the arity of
  `mocked_function`. Because `mocked_function` is a protocol function, its first
  argument is the data structure that implements the protocol, which in this case is
  `protomock`. The `impl` function has no need for this data structure, so it is omitted
  from the `impl` argument list.

  When `expect/4` is invoked, any previously declared stubs for the same `mocked_function`
  will be removed. This ensures that `expect` will fail if the function is called more
  than `invocation_count` times. If `stub/3` is invoked after `expect/4` for the same
  `mocked_function`, the stub will be used after all expectations are fulfilled.

  `expect/4` will raise an `ArgumentError` if `mocked_function` is not a member function
  of the protocol mocked by `protomock`, as indicated via `new/1`.

  ## Examples

  To expect `WeatherAPI.temperature/2` to be called once:

      protomock =
        ProtoMock.new(WeatherAPI)
        |> ProtoMock.expect(&WeatherAPI.temperature/2, fn _lat_long -> {:ok, 30} end)

  To expect `WeatherAPI.temperature/2` to be called five times:

      protomock =
        ProtoMock.new(WeatherAPI)
        |> ProtoMock.expect(&WeatherAPI.temperature/2, 5, fn _lat_long -> {:ok, 30} end)

  To expect `WeatherAPI.temperature/2` to not be called:

      protomock =
        ProtoMock.new(WeatherAPI)
        |> ProtoMock.expect(&WeatherAPI.temperature/2, 0, fn _lat_long -> {:ok, 30} end)

  `expect/4` can be invoked multiple times for the same `mocked_function`, permitting
  different behaviors for each invocation. For example, we could test that our code
  will try an API call three times before giving up:

      protomock =
        ProtoMock.new(WeatherAPI)
        |> ProtoMock.expect(&WeatherAPI.temperature/2, 2, fn _ -> {:error, :unreachable} end)
        |> ProtoMock.expect(&WeatherAPI.temperature/2, 1, fn _ -> {:ok, 30} end)

      lat_long = {0.0, 0.0}

      log = capture_log(fn ->
        humanized_temp = HumanizedWeather.display_temp(lat_long, protomock)
        assert humanized_temp == "It's currently 30 degrees"
      end)

      assert log =~ "attempt 1 failed"
      assert log =~ "attempt 2 failed"
      assert log =~ "attempt 3 succeeded"

      ProtoMock.expect(protomock, &WeatherAPI.temperature/2, 3, fn _ -> {:error, :unreachable} end)

      result = HumanizedWeather.display_temp(lat_long, protomock)
      assert result == "Current temperature is unavailable"

  """
  @spec expect(t(), function(), non_neg_integer(), function()) :: t()
  def expect(protomock, mocked_function, invocation_count \\ 1, impl) do
    assert_protomock_implements!(mocked_function)
    validate_arity!(mocked_function, impl)

    reply = GenServer.call(protomock.pid, {:expect, mocked_function, invocation_count, impl})

    case reply do
      :ok -> protomock
      %ArgumentError{message: msg} -> raise ArgumentError.exception(msg)
    end
  end

  @doc false
  @spec invoke(t(), function(), [any()]) :: t()
  def invoke(protomock, mocked_function, args) do
    reply = GenServer.call(protomock.pid, {:invoke, mocked_function, args})

    case reply do
      {UnexpectedCallError, args} ->
        raise UnexpectedCallError, args

      %{protomock_ref: ref} ->
        receive do
          {^ref, {:protomock_error, e}} ->
            raise e

          {^ref, return_value} ->
            return_value
        end

      return_value ->
        return_value
    end
  end

  @doc """
  Verifies that all expectations have been fulfilled.
  """
  @spec verify!(t()) :: :ok
  def verify!(protomock) do
    failure_messages = GenServer.call(protomock.pid, :verify)

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
    case protocol_exports_function?(state.mocked_protocol, mocked_function) do
      true ->
        updated_stubs = state.stubs |> Map.put(mocked_function, impl)
        updated_state = %{state | stubs: updated_stubs}

        {:reply, :ok, updated_state}

      false ->
        msg =
          "Function #{inspect(mocked_function)} is not defined by protocol #{state.mocked_protocol}"

        {:reply, ArgumentError.exception(msg), state}
    end
  end

  @impl true
  def handle_call({:expect, mocked_function, invocation_count, impl}, _from, state) do
    case protocol_exports_function?(state.mocked_protocol, mocked_function) do
      true ->
        updated_state = add_expectations(mocked_function, invocation_count, impl, state)
        {:reply, :ok, updated_state}

      false ->
        msg =
          "Function #{inspect(mocked_function)} is not defined by protocol #{state.mocked_protocol}"

        {:reply, ArgumentError.exception(msg), state}
    end
  end

  @impl true
  def handle_call({:invoke, mocked_function, args}, {from_pid, _}, state) do
    invocation = %{function: mocked_function, args: args}
    updated_invocations = [invocation | state.invocations]

    expected_count = expected_count(state, mocked_function)
    actual_count = actual_count(updated_invocations, mocked_function)

    cond do
      delegated?(state, mocked_function) ->
        function_name = bare_function_name(mocked_function)
        function_args = [state.delegate] ++ args
        return_value = Kernel.apply(state.mocked_protocol, function_name, function_args)

        {:reply, return_value, state}

      exceeded_expectations?(expected_count, actual_count) ->
        updated_state = %{state | invocations: updated_invocations}
        error_args = {mocked_function, expected_count, actual_count}

        {:reply, {UnexpectedCallError, error_args}, updated_state}

      true ->
        {impl, updated_expectations} = next_impl(state, mocked_function)
        ref = make_ref()

        Task.async(fn ->
          response =
            try do
              return_value = Kernel.apply(impl, args)

              if state.check_runtime_types do
                RuntimeTypeChecker.validate_invocation!(
                  mocked_function,
                  [self()] ++ args,
                  return_value
                )
              end

              return_value
            rescue
              e ->
                {:protomock_error, e}
            end

          send(from_pid, {ref, response})
        end)

        updated_state = %{
          state
          | invocations: updated_invocations,
            expectations: updated_expectations
        }

        {:reply, %{protomock_ref: ref}, updated_state}
      end
  end

  @impl true
  def handle_call(:verify, _from, state) do
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

    {:reply, failure_messages, state}
  end

  @impl true
  def handle_info(_info, state) do
    {:noreply, state}
  end

  # ----- private

  @spec add_expectations(function(), non_neg_integer(), function(), state()) :: state()
  defp add_expectations(mocked_function, invocation_count, impl, state) do
    new_expectations =
      for _ <- Range.new(1, invocation_count, 1) do
        %{
          mocked_function: mocked_function,
          impl: impl,
          pending?: true
        }
      end

    updated_expectations = state.expectations ++ new_expectations

    %{state | expectations: updated_expectations}
  end

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

  @spec delegated?(state(), function()) :: boolean()
  defp delegated?(state, function) do
    state.delegate != nil
    && !has_stubs?(state, function)
    && !has_expectations?(state, function)
  end

  @spec has_stubs?(state(), function()) :: boolean
  def has_stubs?(state, function) do
    Map.get(state.stubs, function) != nil
  end

  @spec has_expectations?(state(), function()) :: boolean
  def has_expectations?(state, function) do
    state.expectations
    |> Enum.any?(fn expectation ->
      expectation.mocked_function == function
    end)
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

  @spec bare_function_name(function()) :: atom()
  defp bare_function_name(function) do
    Function.info(function)[:name]
  end

  @doc false
  def exception_message(function, expected_count, actual_count) do
    function_name = function_name(function)
    expected_times = times(expected_count)
    actual_times = times(actual_count)

    "expected #{function_name} to be called #{expected_times} but it was called #{actual_times}"
  end

  @spec validate_arity!(function(), function()) :: :ok
  defp validate_arity!(mocked_function, impl) when is_function(impl) do
    original_arity = Function.info(mocked_function)[:arity]
    expected_arity = original_arity - 1
    impl_arity = Function.info(impl)[:arity]

    cond do
      impl_arity == expected_arity ->
        :ok

      impl_arity == expected_arity + 1 ->
        message = """
        \n
        The provided implementation function has arity #{impl_arity}, which is equal to the arity of #{inspect(mocked_function)}.

        The arity of the provided implementation function must be *one less than* the arity of the function being mocked.

        This is because the first argument of #{inspect(mocked_function)} is the data structure that implements the protocol,
        which in this case is a ProtoMock instance. The implementation function has no reason to access the ProtoMock instance,
        so we have chosen to omit it from the implementation function's argument list.
        """

        raise ArgumentError.exception(message)

      true ->
        message = """
        \n
        The provided implementation function has arity #{impl_arity}. The expected arity is #{expected_arity}.

        The arity of the provided implementation function must be *one less than* the arity of #{inspect(mocked_function)}.

        This is because the first argument of #{inspect(mocked_function)} is the data structure that implements the protocol,
        which in this case is a ProtoMock instance. The implementation function has no reason to access the ProtoMock instance,
        so we have chosen to omit it from the implementation function's argument list.
        """

        raise ArgumentError.exception(message)
    end
  end

  @spec assert_protomock_implements!(function()) :: :ok
  defp assert_protomock_implements!(function) do
    [{:module, module}, {:name, name}, {:arity, arity} | _rest] =
      try do
        Function.info(function)
      rescue
        _ in ArgumentError ->
          message = """
          #{inspect(function)} is not a function. To pass a function to ProtoMock.stub/3 or ProtoMock.expect/4,
          use a function capture, for example &Enumerable.count/1

          If you find this error puzzling, double check for compiler warnings related to #{inspect(function)}.
          """

          raise ArgumentError.exception(message)
      end

    try do
      :ok = Protocol.assert_protocol!(module)
    rescue
      _ in ArgumentError ->
        message = """
        #{module} is not recognized as a protocol.

        If you find this error puzzling, double-check for compiler warnings related to #{inspect(function)}.
        Perhaps you're missing an alias or have a misspelling.
        """

        raise ArgumentError.exception(message)
    end

    try do
      :ok = Protocol.assert_impl!(module, __MODULE__)
    rescue
      _ in ArgumentError ->
        message = """
        ProtoMock does not implement the #{module} protocol. #{module} must be the same protocol passed to `ProtoMock.new/1`.

        If you find this error puzzling, double-check for compiler warnings related to #{inspect(function)}.
        """

        raise ArgumentError.exception(message)
    end

    case function_exported?(module, name, arity) do
      true ->
        :ok

      false ->
        message = """
        #{inspect(function)} is not a function exported by #{module}.

        Look for compiler warnings related to #{inspect(function)}.

        Double-check your function name and function arity.
        """

        raise ArgumentError.exception(message)
    end
  end

  @spec ensure_protomock_started() :: :ok
  defp ensure_protomock_started() do
    :ok = ImplCreator.ensure_started()
    :ok = ConfigAgent.ensure_started()
    :ok
  end

  @spec protocol_exports_function?(module(), function()) :: boolean()
  defp protocol_exports_function?(nil, _function), do: true

  defp protocol_exports_function?(protocol, function) do
    [module, name, arity] =
      Function.info(function)
      |> Keyword.take([:module, :name, :arity])
      |> Keyword.values()

    module == protocol && function_exported?(module, name, arity)
  end

  @spec check_runtime_types?(keyword()) :: boolean()
  defp check_runtime_types?(opts) do
    Keyword.get(opts, :check_runtime_types, ConfigAgent.get(:check_runtime_types))
  end

  @spec create_impl(module()) :: :ok
  defp create_impl(protocol) do
    :ok = ensure_protomock_started()
    :ok = ProtoMock.ImplCreator.ensure_impl_created(protocol)
    :ok
  end
end
