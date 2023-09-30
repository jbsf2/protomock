defmodule ProtoMock.RuntimeTypeChecker do
  @moduledoc false

  alias ProtoMock.TypeEngine

  @typep function_name :: atom()
  @typep function_typespec :: {:type, non_neg_integer(), :fun, [arg_typespec(), ...]}
  @typep arg_typespec ::
           {:remote_type, 0, [any(), ...]}
           | {:type, non_neg_integer(), atom(), [arg_typespec(), ...]}

  @spec validate_invocation!(function(), [any()], any()) :: :ok
  def validate_invocation!(mocked_function, args, return_value) do
    for typespec <- fetch_typespecs(mocked_function) do
      validate_args!(mocked_function, args, typespec)
      validate_return_value!(mocked_function, return_value, typespec)
    end

    :ok
  end

  @spec fetch_typespecs(function()) :: [function_typespec()]
  defp fetch_typespecs(mocked_function) do
    {module, function_name, arity} = describe_function(mocked_function)

    case Code.Typespec.fetch_specs(module) do
      {:ok, specs} ->
        specs
        |> Enum.find_value([], fn
          {{^function_name, ^arity}, typespecs} -> typespecs
          _ -> false
        end)
        |> Enum.map(&TypeEngine.replace_user_types(&1, module))

      :error ->
        []
    end
  end

  @spec arg_typespec(function_typespec(), non_neg_integer()) :: arg_typespec()
  defp arg_typespec(function_typespec, arg_index) do
    {:type, _, :fun, [{:type, _, :product, arg_typespecs}, _]} = function_typespec
    Enum.at(arg_typespecs, arg_index)
  end

  @spec validate_args!(function(), [any()], function_typespec()) :: :ok
  defp validate_args!(_mocked_function, [], _typespec) do
    :ok
  end

  defp validate_args!(mocked_function, args, typespec) do
    args
    |> Enum.zip(0..(length(args) - 1))
    |> Enum.each(fn {arg, index} ->
      arg_typespec = arg_typespec(typespec, index)

      case TypeEngine.match_type(arg, arg_typespec) do
        {:error, _reasons} ->
          message = """
          Invalid argument passed to function #{inspect(mocked_function)}:

          #{nth(index)} is invalid according to your typespecs

          value: #{inspect(arg)}
          """

          raise RuntimeError, message

        :ok ->
          :ok
      end
    end)
  end

  @spec validate_return_value!(function(), any(), function_typespec()) :: :ok
  defp validate_return_value!(mocked_function, return_value, typespec) do
    {:type, _, :fun, [_, return_type]} = typespec

    case TypeEngine.match_type(return_value, return_type) do
      {:error, _reasons} ->
        message = """
        Invalid value returned from fake implementation for #{inspect(mocked_function)}.

        value: #{inspect(return_value)}

        The type of the returned value does not satisfy the typespec for #{inspect(mocked_function)}.
        """

        raise RuntimeError, message

      :ok ->
        :ok
    end
  end

  @spec describe_function(function()) :: {module(), function_name(), arity()}
  defp describe_function(function) do
    [{:module, module}, {:name, function_name}, {:arity, arity} | _rest] = Function.info(function)

    {module, function_name, arity}
  end

  @spec nth(integer()) :: String.t()
  defp nth(0), do: "first argument"
  defp nth(1), do: "second argument"
  defp nth(2), do: "third argument"
  defp nth(n) when n < 10, do: "#{n + 1}th argument"
  defp nth(n), do: "argument at position #{n}"
end
