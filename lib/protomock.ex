defmodule ProtoMock do
  @moduledoc ~S"""
  ProtoMock is a library for mocking Elixir protocols.

  ## Motivation / use case

  ProtoMock was built to support using protocols, rather than behaviours and/or plain
  modules, for modeling and accessing external APIs. When external APIs are modeled with
  protocols, ProtoMock can provide mocking capabilities.

  Modeling external APIs with protocols provides these benefits:

  * API transparency
  * IDE navigability
  * Compiler detection of api errors

  It is not expected that ProtoMock would be useful for more traditional protocol use
  cases, wherein protocols such as `Enum` provide a common interface for operating on
  disparate data structures. In such situations, there is no value in testing with mocks,
  therefore ProtoMock has no role.

  ## Example

  Following the traditional [Mox example](https://hexdocs.pm/mox/Mox.html#module-example),
  imagine that we have an app that has to display the weather. To retrieve weather data,
  we use an external weather API called AcmeWeather, and we model the API with our own
  protocol:

      defprotocol MyApp.WeatherAPI do
        @type lat_long :: {float(), float()}
        @type api_result :: {:ok, float()} | {:error, String.t()}

        @spec temperature(t(), lat_long()) :: api_result()
        def temperature(weather_api, lat_long)

        @spec humidity(t(), lat_long()) :: api_result()
        def humidity(weather_api, lat_long)
      end

  We create a "real" implementation of `WeatherAPI` that calls out to the
  AcmeWeather api client:

      create_impl MyApp.WeatherAPI, for: AcmeWeather.ApiConfig do
        def temperature(api_config, {lat, long}) do
          AcmeWeather.Client.get_temperature(lat, long, api_config)
        end

        def humidity(api_config, {lat, long}) do
          AcmeWeather.Client.get_humidity(lat, long, api_config)
        end
      end

  For testing, however, we want to mock the service.

  As a first step, we define an implementation of `WeatherAPI` that proxies
  its function calls to an instance of `ProtoMock`. For creating such
  implementations, the `ProtoMock` module provides the function `create_impl/1`. We can use
  that function in our `test_helper.exs` or similar test suite config file:

      ProtoMock.create_impl(MyApp.WeatherAPI)

  With this implementation now loaded into the BEAM, we are prepared to use instances
  of `ProtoMock` to dispatch `WeatherAPI` functions.

  For this example, we'll focus on the simplest use case scenario for our protocol: a
  function that takes a protocol implementation as an input parameter. Other scenarios,
  such as using protocols within GenServers or using protocols when implementations
  aren't passed as parameters, are discussed elsewhere.

  Continuing with the [Mox example](https://hexdocs.pm/mox/Mox.html#module-example),
  imagine that our application code looks like:

      defmodule MyApp.HumanizedWeather do
        alias MyApp.WeatherAPI

        def display_temp({lat, long}, weather_api \\ default_weather_api()) do
          {:ok, temp} = WeatherAPI.temperature(weather_api, {lat, long})
          "Current temperature is #{temp} degrees"
        end

        def display_humidity({lat, long}, weather_api \\ default_weather_api()) do
          {:ok, humidity} = WeatherAPI.humidity(weather_api, {lat, long})
          "Current humidity is #{humidity}%"
        end

        defp default_weather_api() do
          Application.get_env(MyApp, :weather_api)
        end
      end

  In our test, we're ready to create instances of ProtoMock and use functions `expect/4`,
  `stub/3` and `verify!/1`.

      defmodule MyApp.HumanizedWeatherTest do
        use ExUnit.Case, async: true

        alias MyApp.HumanizedWeather
        alias MyApp.WeatherAPI

        test "gets and formats temperature" do
          protomock =
            ProtoMock.new()
            |> ProtoMock.expect(&WeatherAPI.temperature/2, fn _lat_long -> {:ok, 30} end)

          assert HumanizedWeather.display_temp({50.06, 19.94}, protomock) ==
                  "Current temperature is 30 degrees"

          ProtoMock.verify!(protomock)
        end

        test "gets and formats humidity" do
          protomock =
            ProtoMock.new()
            |> ProtoMock.stub(&WeatherAPI.humidity/2, fn _lat_long -> {:ok, 60} end)

          assert HumanizedWeather.display_humidity({50.06, 19.94}, protomock) ==
                "Current humidity is 60%"
        end
      end

  ## Under the hood: a GenServer

  The `ProtoMock` module is a GenServer. Each time we create a `ProtoMock` with `new/0`,
  we start a new `ProtoMock` GenServer that is linked to the calling process - typically
  an ExUnit test process. When the test pid dies, the `ProtoMock` GenServer dies with it.

  `expect/4` and `stub/3` modify the `ProtoMock` GenServer state to tell the ProtoMock
  how it will be used and how it should respond. As a `ProtoMock` instance is used to
  dispatch functions of a mocked protocol, the instance records each function invocation.
  `verify!/1` compares the function invocations to the expectations defined via
  `expect/4`, and raises in case of an expectations mismatch.

  ## Comparison to [Mox](https://hexdocs.pm/mox/Mox.html)

  In order to feel familiar to developers, the ProtoMock API was modeled after the Mox API.

  Some differences worth noting:

  * ProtoMock has no concept of private mode or global mode. It's expected that each ExUnit
    test will create its own instance or instances of `ProtoMock` that are implicitly private
    to the test pid, thereby always being safe for `async: true`
  * Similarly, ProtoMock has no concept of allowances. Each `ProtoMock` instance is just a
    GenServer that can be used freely and without worry by any process spawned by an
    ExUnit test process (provided that the child process does not interact with other tests).
  * Rather than specificying expectations and stubs with a module name and a function name,
    e.g. `(MyAPIModule, :my_api_function ...)`, ProtoMock uses function captures, e.g.
    `&MyApiProtocol.my_api_function/2`. As a benefit, api mismatches between actual code and
    expectations/stubs will be caught at compile time.
  * `stub_with` and `verify_on_exit` are not implemented, but may be implemented in future
    versions if there's interest.

  ## Goals and philosophy

  ProtoMock aims to support and enable the notion that each test should be its own
  little parallel universe, without any modifiable state shared between tests. It
  intentionally avoids practices common in mocking libraries such as setting/resetting
  Application environment variables. Such practices create potential collisions between
  tests that must be avoided with `async: false`. ProtoMock believes `async` should
  always be `true`!

  ProtoMock aims to provide an easy-on-the-eyes, function-oriented API that doesn't
  rely on macros and doesn't require wrapping test code in closures.

  """
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

  # child_spec/1 is injected by GenServer. We override it and set @doc false
  # so that it doesn't appear in docs.
  @doc false
  def child_spec(_), do: nil

  @doc """
  Creates an implementation of `protocol` for the `ProtoMock` module, thereby preparing
  `ProtoMock` to be used in mocking the protocol.

  The implementation that is generated dispatches functions on `protocol` by proxying
  them to an instance of `ProtoMock`.

  The expected use of `create_impl/1` is to call it in within `test_helper.exs`, for each
  protocol to be mocked using ProtoMock. For example:

          ProtoMock.create_impl(MyProtocol)
          ProtoMock.create_impl(MyOtherProtocol)

  """
  @spec create_impl(module()) :: :ok
  def create_impl(protocol) do
    Protocol.assert_protocol!(protocol)

    if impl_exists?(protocol) do
      message = "ProtoMock already has an implementation defined for protocol #{protocol}"
      raise ArgumentError, message
    end

    quoted =
      quote do
        defimpl unquote(protocol), for: unquote(ProtoMock) do
          (unquote_splicing(impl_functions(protocol)))
        end
      end

    {_term, _binding} = Code.eval_quoted(quoted)
    :ok
  end

  @doc """
  Creates a new instance of `ProtoMock`

  After creating a new `ProtoMock`, tests can add expectations and stubs to the instance
  using `expect/4` and `stub/3`. With expectations and stubs in place, the `ProtoMock`
  instance can be provided to the code under test, and used by the code under test
  where it expects an implementation of any mocked protocols.

  The `ProtoMock` module is a GenServer. `new/0` starts a new instance of the GenServer
  that is linked to the calling process, typically an ExUnit test pid. When the test pid
  exits, any child `ProtoMock` GenServers also exit.
  """
  @spec new() :: t()
  def new() do
    state = %{stubs: %{}, expectations: [], invocations: []}
    {:ok, pid} = GenServer.start_link(__MODULE__, state)
    %__MODULE__{pid: pid}
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

  ## Example

  To allow `WeatherAPI.temperature/2` to be dispatched to a `ProtoMock` instance any
  number of times:

      protomock =
        ProtoMock.new()
        |> ProtoMock.stub(&WeatherAPI.temperature/2, fn _lat_long -> {:ok, 30} end)

  `stub/3` will overwrite any previous calls to `stub/3`.
  """
  @spec stub(t(), function(), function()) :: t()
  def stub(protomock, mocked_function, impl) do
    :ok = GenServer.call(protomock.pid, {:stub, mocked_function, impl})
    protomock
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

  ## Examples

  To expect `WeatherAPI.temperature/2` to be called once:

      protomock =
        ProtoMock.new()
        |> ProtoMock.expect(&WeatherAPI.temperature/2, fn _lat_long -> {:ok, 30} end)

  To expect `WeatherAPI.temperature/2` to be called five times:

      protomock =
        ProtoMock.new()
        |> ProtoMock.expect(&WeatherAPI.temperature/2, 5, fn _lat_long -> {:ok, 30} end)

  To expect `WeatherAPI.temperature/2` to not be called:

      protomock =
        ProtoMock.new()
        |> ProtoMock.expect(&WeatherAPI.temperature/2, 0, fn _lat_long -> {:ok, 30} end)

  `expect/4` can be invoked multiple times for the same `mocked_function`, permitting
  different behaviors for each invocation. For example, we could test that our code
  will try an API call three times before giving up:

      protomock =
        ProtoMock.new()
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
    :ok = GenServer.call(protomock.pid, {:expect, mocked_function, invocation_count, impl})
    protomock
  end

  @doc false
  @spec invoke(t(), function(), [any()]) :: t()
  def invoke(protomock, mocked_function, args) do
    reply = GenServer.call(protomock.pid, {:invoke, mocked_function, args})

    case reply do
      {UnexpectedCallError, args} ->
        raise UnexpectedCallError, args

      ref ->
        receive do
          {^ref, {:protomock_error, e}} -> raise e
          {^ref, response} -> response
        end
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
  def handle_call({:invoke, mocked_function, args}, {from_pid, _}, state) do
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
        ref = make_ref()

        Task.async(fn ->
          response = try do
            Kernel.apply(impl, args)
          rescue
            e -> {:protomock_error, e}
          end
          send(from_pid, {ref, response})
        end)

        updated_state = %{
          state
          | invocations: updated_invocations,
            expectations: updated_expectations
        }

        {:reply, ref, updated_state}
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

  @doc false
  def exception_message(function, expected_count, actual_count) do
    function_name = function_name(function)
    expected_times = times(expected_count)
    actual_times = times(actual_count)

    "expected #{function_name} to be called #{expected_times} but it was called #{actual_times}"
  end

  # For each function defined by the given protocol, `impl_functions` generates
  # an implementation function that proxies to a ProtoMock.
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
            unquote(args)
          )
        end
      end
    end)
  end

  @spec impl_exists?(module()) :: boolean()
  defp impl_exists?(protocol) do
    impl = Module.concat(protocol, ProtoMock)
    module_exists?(impl) and impl.__impl__(:protocol) == protocol
  end

  @spec module_exists?(module()) :: boolean()
  defp module_exists?(module), do: function_exported?(module, :__info__, 1)
end
