defmodule ProtoMockTest do
  use ExUnit.Case

  alias ProtoMock.VerificationError

  describe "expect" do
    test "works in the simple case" do
      protomock = mock_add()

      assert Calculator.add(protomock, 1, 2) == 3
    end

    test "is order-insensitive" do
      protomock =
        ProtoMock.new()
        |> ProtoMock.expect(&Calculator.add/3, 3, fn _, x, y -> x + y end)
        |> ProtoMock.expect(&Calculator.mult/3, 2, fn _, x, y -> x * y end)

      assert Calculator.add(protomock, 1, 1) == 2
      assert Calculator.mult(protomock, 1, 1) == 1
      assert Calculator.add(protomock, 2, 4) == 6
      assert Calculator.mult(protomock, 2, 4) == 8
      assert Calculator.add(protomock, 5, 4) == 9
    end

    test "allows asserting that the function has not been called" do
      protomock =
        ProtoMock.new()
        |> ProtoMock.expect(&Calculator.add/3, 0, fn _, x, y -> x + y end)

      msg = ~r"expected Calculator.add/3 to be called 0 times but it was called once"

      assert_raise ProtoMock.UnexpectedCallError, msg, fn ->
        Calculator.add(protomock, 2, 3) == 5
      end
    end

    test "can be recharged" do
      protomock =
        ProtoMock.new()
        |> ProtoMock.expect(&Calculator.add/3, 1, fn _, x, y -> x + y end)

      assert Calculator.add(protomock, 1, 2) == 3

      protomock |> ProtoMock.expect(&Calculator.add/3, 1, fn _, x, y -> x + y end)

      assert Calculator.add(protomock, 2, 2) == 4
    end

    test "raises if a non-ProtoMock is given" do
      assert_raise ArgumentError, ~r"got Unknown instead", fn ->
        ProtoMock.expect(Unknown, &Calculator.add/3, fn _, x, y -> x + y end)
      end

      assert_raise ArgumentError, ~r"got String instead", fn ->
        ProtoMock.expect(String, &Calculator.add/3, fn _, x, y -> x + y end)
      end
    end

    test "raises if there are no expectations" do
      msg = ~r"expected Calculator.add\/3 to be called 0 times but it was called once"
      assert_raise ProtoMock.UnexpectedCallError, msg, fn ->
        Calculator.add(ProtoMock.new(), 2, 3) == 5
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
      |> ProtoMock.expect(&Calculator.add/3, fn _, x, y -> x + y end)

    protomock
  end
end
