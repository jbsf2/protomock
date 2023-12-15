defmodule ProtoMock.ImplCreator do
  # The ImplCreator agent exists to ensure that impl creation is
  # single-threaded, thereby avoiding race conditions that could
  # lead to impl modules being redefined, with compiler warnings
  # generated as a result.
  #
  # Doing it this way means developers don't have to remember to
  # create implementations in test_helper.exs or equivalent. Instead,
  # implementations are created on demand via ProtoMock.new/1,
  # with "async: true" safely supported.

  @moduledoc false

  @typep quoted_expression :: {atom() | tuple(), keyword(), list() | atom()}

  @spec ensure_started() :: :ok
  def ensure_started() do
    if Process.whereis(__MODULE__) == nil do
      # If tests are run in parallel, it's possible that multiple test
      # processes might try to start the agent at the same time.
      # Only one will succeed. We choose to live with the (harmless) race condition
      # in favor of developer ergonomics, in that developers don't have
      # to explicitly start any global ProtoMock processes.
      case Agent.start(fn -> MapSet.new() end, name: __MODULE__) do
        {:ok, _pid} ->
          :ok

        {:error, {:already_started, _pid}} ->
          :ok

        {:error, reason} ->
          raise "Failed to start ProtoMock.ImplCreator: #{inspect(reason)}"
      end
    else
      :ok
    end
  end

  @spec ensure_impl_created(module()) :: :ok
  def ensure_impl_created(protocol) do
    {:module, _} = Code.ensure_loaded(protocol)
    Protocol.assert_protocol!(protocol)

    Agent.update(__MODULE__, fn implemented_protocols ->
      case MapSet.member?(implemented_protocols, protocol) do
        true ->
          implemented_protocols

        false ->
          :ok = create_impl(protocol)
          MapSet.put(implemented_protocols, protocol)
      end
    end)

    :ok
  end

  @spec create_impl(module()) :: :ok
  defp create_impl(protocol) do
    quoted =
      quote do
        defimpl unquote(protocol), for: unquote(ProtoMock) do
          (unquote_splicing(impl_functions(protocol)))
        end
      end

    {_term, _binding} = Code.eval_quoted(quoted)

    :ok
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
end
