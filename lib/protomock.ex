defmodule ProtoMock do

  use GenServer

  defmodule VerificationError do
    defexception [:message]
  end

  @type expectation :: %{
    mocked_function: function(),
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

  @spec expect(t(), function(), function()) :: t()
  def expect(proto_mock, mocked_function, impl) do
    :ok = GenServer.call(proto_mock.name, {:expect, mocked_function, impl})
    proto_mock
  end

  @spec respond(t(), function(), [any()]) :: t()
  def respond(proto_mock, mocked_function, args \\ []) do
    GenServer.call(proto_mock.name, {:respond, mocked_function, args})
  end

  @spec verify!(t()) :: t()
  def verify!(proto_mock) do
    state = GenServer.call(proto_mock.name, :state)
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
  def handle_call({:expect, mocked_function, impl}, _from, state) do
    new_expectation = %{
      mocked_function: mocked_function,
      impl: impl
    }
    updated_expectations = state.expectations |> List.insert_at(-1, new_expectation)

    updated_state = %{state | expectations: updated_expectations}

    {:reply, :ok, updated_state}
  end

  @impl true
  def handle_call({:respond, mocked_function, args}, _from, state) do
    expectation = state.expectations |> Enum.at(length(state.invocations))

    invocation = %{function: mocked_function, args: args}
    updated_invocations = [invocation | state.invocations]

    response = Kernel.apply(expectation.impl, args)

    updated_state = %{state | invocations: updated_invocations}

    {:reply, response, updated_state}
  end

  @impl true
  def handle_call(:state, _from, state) do
    {:reply, state, state}
  end

  defp random_genserver_name() do
    random = :rand.uniform(10_000_000_000)
    random |> Integer.to_string() |> String.to_atom()
  end
end
