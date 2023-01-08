defmodule ProtoMock.ImplCreatorTest do
  use ExUnit.Case

  alias ProtoMock.ImplCreator

  describe "create_protocol_impl" do

    test "proxies all the protocol functions to the protomock" do
      impl_mod = ImplCreator.create_protocol_impl(Calculator, :foo)

      protomock =
        ProtoMock.new()
        |> ProtoMock.expect(&Calculator.add/3, fn _, _, _ -> :add end)
        |> ProtoMock.expect(&Calculator.mult/3, fn _, _, _ -> :mult end)
        |> ProtoMock.expect(&Calculator.sqrt/2, fn _, _ -> :sqrt end)
        |> ProtoMock.expect(&Calculator.rand/1, fn _ -> :rand end)

      impl_struct = impl_mod.new(protomock)

      assert Calculator.add(impl_struct, 1, 1) == :add
      assert Calculator.mult(impl_struct, 1, 1) == :mult
      assert Calculator.sqrt(impl_struct, 1) == :sqrt
      assert Calculator.rand(impl_struct) == :rand

      assert ProtoMock.verify!(protomock) == :ok
    end
  end

end
