defmodule ProtoMockTest do
  use ExUnit.Case

  alias ProtoMock.VerificationError

  test "it returns the expected data" do
    protomock = create_mock()

    assert Calculator.add(protomock, 1, 2) == 3
  end

  describe "verification" do
    test "when expectatons have been met, it returns :ok" do
      protomock = create_mock()

      Calculator.add(protomock, 1, 2)

      assert ProtoMock.verify!(protomock) == :ok
    end

    test "when expectations have not been met, it throws" do
      protomock = create_mock()

      assert_raise VerificationError, fn -> ProtoMock.verify!(protomock) end
    end
  end

  defp create_mock() do
    protomock =
      ProtoMock.new()
      |> ProtoMock.expect(&Calculator.add/3, fn _, int1, int2 -> int1 + int2 end)

      protomock
  end
end
