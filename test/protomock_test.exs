defmodule ProtoMockTest do
  use ExUnit.Case

  alias ProtoMock.VerificationError

  describe "expect" do
    test "works in the simple case" do
      protomock = mock_add()

      assert Calculator.add(protomock, 1, 2) == 3
    end

    test "allows asserting that the function has not been called" do
      protomock =
        ProtoMock.new()
          |> ProtoMock.expect(&Calculator.add/3, 0, fn _, int1, int2 -> int1 + int2 end)

      msg = ~r"expected Calculator.add/3 to be called 0 times but it was called once"

      assert_raise ProtoMock.UnexpectedCallError, msg, fn ->
        Calculator.add(protomock, 2, 3) == 5
      end
    end
  end

  describe "verify" do
    test "when expectatons have been met, it returns :ok" do
      protomock = mock_add()

      Calculator.add(protomock, 1, 2)

      assert ProtoMock.verify!(protomock) == :ok
    end

    test "when expectations have not been met, it throws" do
      protomock = mock_add()

      assert_raise VerificationError, fn -> ProtoMock.verify!(protomock) end
    end
  end

  defp mock_add() do
    protomock =
      ProtoMock.new()
      |> ProtoMock.expect(&Calculator.add/3, fn _, int1, int2 -> int1 + int2 end)

    protomock
  end
end
