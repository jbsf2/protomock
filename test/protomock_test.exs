defmodule ProtoMockTest do
  use ExUnit.Case

  alias ProtoMock.VerificationError

  test "it returns the expected data" do
    {_protomock, fake_greeter} = create_mock()

    assert Greeter.greet(fake_greeter, "mon ami") == "Bonjour, mon ami"
  end

  describe "verification" do
    test "when expectatons have been met, it returns :ok" do
      {protomock, fake_greeter} = create_mock()

      Greeter.greet(fake_greeter, "mon ami")

      assert ProtoMock.verify!(protomock) == :ok
    end

    test "when expectations have not been met, it throws" do
      {protomock, _fake_greeter} = create_mock()

      assert_raise VerificationError, fn -> ProtoMock.verify!(protomock) end
    end
  end

  defp create_mock() do
    protomock =
      ProtoMock.new()
      |> ProtoMock.expect(&Greeter.greet/2, fn greetee -> "Bonjour, #{greetee}" end)

    fake_greeter = %FakeGreeter{protomock: protomock}

    {protomock, fake_greeter}
  end
end
