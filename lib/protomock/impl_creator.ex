defmodule ProtoMock.ImplCreator do

  def create_protocol_impl(protocol_mod, impl_mod) do

    quoted =
      quote do
        defstruct [:protomock]

        def new(protomock) do
          %__MODULE__{protomock: protomock}
        end

        defimpl unquote(protocol_mod) do
          unquote_splicing(impl_functions(protocol_mod))
        end
      end


    {:module, ^impl_mod, _, _} = Module.create(impl_mod, quoted, Macro.Env.location(__ENV__))

    impl_mod
  end

  defp impl_functions(protocol_mod) do
    protocol_mod.__protocol__(:functions)
    |> Enum.map(fn {function_name, arity} ->
      impl_struct = Macro.var(:impl_struct, __MODULE__)
      mocked_function = Function.capture(protocol_mod, function_name, arity)
      args = Range.new(1, arity-1, 1) |> Enum.map(&Macro.var(:"arg#{&1}", __MODULE__))

      quote do
        def unquote(function_name)(unquote(impl_struct), unquote_splicing(args)) do
          ProtoMock.invoke(
            impl_struct.protomock,
            unquote(mocked_function),
            unquote([impl_struct | args])
          )
        end
      end
    end)
  end
end
