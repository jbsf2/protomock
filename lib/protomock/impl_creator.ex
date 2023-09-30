defmodule ProtoMock.ImplCreator do
  # The ImplCreator Agent exists to ensure that impl creation is
  # single-threaded, thereby avoiding race conditions that could
  # lead to impl modules being redefined, with compiler warnings
  # generated as a result.
  #
  # Doing it this way means developers don't have to remember to
  # call create_impl specifically in test_helper.exs or equivalent.
  # They can call it from anywhere, any number of times, and it
  # will just work - as long as create_impl is called before ProtoMock
  # is used to mock a given protocol.

  @moduledoc false

  @typep quoted_expression :: {atom() | tuple(), keyword(), list() | atom()}

  def start_link() do
    Agent.start_link(fn -> MapSet.new() end, name: __MODULE__)
  end

  @spec ensure_impl_created(module()) :: :ok
  def ensure_impl_created(protocol) do
    Code.ensure_loaded(protocol)
    Protocol.assert_protocol!(protocol)

    Agent.update(__MODULE__, fn implemented_protocols ->
      case MapSet.member?(implemented_protocols, protocol) do
        true ->
          implemented_protocols

        false ->
          create_impl(protocol)
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
