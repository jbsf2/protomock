defmodule ProtoMockTest do
  use ExUnit.Case

  alias ProtoMock.VerificationError

  describe "creating protocol implementations" do
    test "when there is no existing impl for Protomock, it creates one" do
      defprotocol CreateImplTest1 do
        def hello(impl)
      end

      protomock =
        ProtoMock.new(CreateImplTest1)
        |> ProtoMock.expect(&CreateImplTest1.hello/1, fn -> "hello, world!" end)

      assert CreateImplTest1.hello(protomock) == "hello, world!"

      assert ProtoMock.verify!(protomock) == :ok
    end

    test "is idempotent" do
      defprotocol CreateImplTest2 do
        def hello(impl)
      end

      protomock1 =
        ProtoMock.new(CreateImplTest2)
        |> ProtoMock.expect(&CreateImplTest2.hello/1, fn -> "hello from protomock1!" end)

      protomock2 =
        ProtoMock.new(CreateImplTest2)
        |> ProtoMock.expect(&CreateImplTest2.hello/1, fn -> "hello from protomock2!" end)

      assert CreateImplTest2.hello(protomock1) == "hello from protomock1!"
      assert ProtoMock.verify!(protomock1) == :ok

      assert CreateImplTest2.hello(protomock2) == "hello from protomock2!"
      assert ProtoMock.verify!(protomock2) == :ok
    end

    test "when the argument is not a protocol, it raises an error" do
      assert_raise ArgumentError, "Map is not a protocol", fn ->
        ProtoMock.new(Map)
      end
    end
  end

  describe "expect" do
    test "works in the simple case" do
      protomock = mock_add()

      assert Calculator.add(protomock, 1, 2) == 3
    end

    test "is order-insensitive" do
      protomock =
        ProtoMock.new(Calculator)
        |> ProtoMock.expect(&Calculator.add/3, 3, fn x, y -> x + y end)
        |> ProtoMock.expect(&Calculator.mult/3, 2, fn x, y -> x * y end)

      assert Calculator.add(protomock, 1, 1) == 2
      assert Calculator.mult(protomock, 1, 1) == 1
      assert Calculator.add(protomock, 2, 4) == 6
      assert Calculator.mult(protomock, 2, 4) == 8
      assert Calculator.add(protomock, 5, 4) == 9
    end

    test "allows asserting that the function has not been called" do
      protomock =
        ProtoMock.new(Calculator)
        |> ProtoMock.expect(&Calculator.add/3, 0, fn x, y -> x + y end)

      msg = ~r"expected Calculator.add/3 to be called 0 times but it was called once"

      assert_raise ProtoMock.UnexpectedCallError, msg, fn ->
        Calculator.add(protomock, 2, 3) == 5
      end
    end

    test "can be 'recharged'" do
      protomock = mock_add()

      assert Calculator.add(protomock, 1, 2) == 3

      protomock |> ProtoMock.expect(&Calculator.add/3, 1, fn x, y -> x + y end)

      assert Calculator.add(protomock, 2, 2) == 4
    end

    test "raises if there are no expectations" do
      msg = ~r"expected Calculator.add\/3 to be called 0 times but it was called once"

      assert_raise ProtoMock.UnexpectedCallError, msg, fn ->
        Calculator.add(ProtoMock.new(), 2, 3) == 5
      end
    end

    test "raises if expectations are exceeded" do
      protomock = mock_add()

      assert Calculator.add(protomock, 1, 2) == 3

      msg = "expected Calculator.add/3 to be called once but it was called twice"

      assert_raise ProtoMock.UnexpectedCallError, msg, fn ->
        Calculator.add(protomock, 2, 3)
      end

      ProtoMock.expect(protomock, &Calculator.add/3, fn x, y -> x + y end)

      msg = "expected Calculator.add/3 to be called twice but it was called 3 times"

      assert_raise ProtoMock.UnexpectedCallError, msg, fn ->
        Calculator.add(protomock, 2, 3)
      end
    end

    test "verifies that the mocked function is a member function of a protocol implemented by ProtoMock" do
      protomock = ProtoMock.new(Calculator)

      assert_raise ArgumentError, ~r/not a function/, fn ->
        ProtoMock.expect(protomock, :not_a_function, fn -> nil end)
      end

      assert_raise ArgumentError, ~r/is not recognized/, fn ->
        ProtoMock.expect(protomock, &Map.new/0, fn -> nil end)
      end

      assert_raise ArgumentError, ~r/does not implement/, fn ->
        ProtoMock.expect(protomock, &Enumerable.count/1, fn -> nil end)
      end

      assert_raise ArgumentError, ~r/not a function exported by/, fn ->
        function = Function.capture(Calculator, :add, 4)
        ProtoMock.expect(protomock, function, fn -> nil end)
      end
    end
  end

  describe "verify" do
    test "with no expectations, it returns :ok" do
      protomock = ProtoMock.new(Calculator)

      assert ProtoMock.verify!(protomock) == :ok
    end

    test "if expectations have been met, it returns :ok" do
      protomock = mock_add()

      Calculator.add(protomock, 1, 2)

      assert ProtoMock.verify!(protomock) == :ok
    end

    test "if expectations have not been met, it raises" do
      protomock = mock_add()

      msg = "expected Calculator.add/3 to be called once but it was called 0 times"

      assert_raise VerificationError, msg, fn ->
        ProtoMock.verify!(protomock)
      end
    end

    test "it 'recharges' when expectations 'recharge'" do
      protomock = mock_add()

      Calculator.add(protomock, 1, 2)

      assert ProtoMock.verify!(protomock) == :ok

      ProtoMock.expect(protomock, &Calculator.add/3, fn x, y -> x + y end)

      msg = "expected Calculator.add/3 to be called twice but it was called once"

      assert_raise VerificationError, msg, fn ->
        ProtoMock.verify!(protomock)
      end
    end

    test "it looks at all expected functions" do
      protomock =
        mock_add()
        |> ProtoMock.expect(&Calculator.mult/3, fn x, y -> x * y end)

      Calculator.add(protomock, 1, 2)

      msg = "expected Calculator.mult/3 to be called once but it was called 0 times"

      assert_raise VerificationError, msg, fn ->
        ProtoMock.verify!(protomock)
      end
    end

    test "it reports all errors at once" do
      protomock =
        mock_add()
        |> ProtoMock.expect(&Calculator.mult/3, fn x, y -> x * y end)

      msg1 = "expected Calculator.add/3 to be called once but it was called 0 times"
      msg2 = "expected Calculator.mult/3 to be called once but it was called 0 times"

      try do
        ProtoMock.verify!(protomock)
      rescue
        e in VerificationError ->
          assert e.message =~ msg1
          assert e.message =~ msg2
      else
        _ -> flunk("Expected VerificationError but did not get one")
      end
    end
  end

  describe "stub" do
    test "allows repeated invocations" do
      protomock = stub_add()

      assert Calculator.add(protomock, 1, 2) == 3
      assert Calculator.add(protomock, 3, 4) == 7
    end

    test "does not fail verification if not called" do
      protomock = stub_add()

      assert ProtoMock.verify!(protomock) == :ok
    end

    test "gives expectations precedence" do
      protomock =
        ProtoMock.new(Calculator)
        |> ProtoMock.stub(&Calculator.add/3, fn x, y -> x + y end)
        |> ProtoMock.expect(&Calculator.add/3, fn _x, _y -> -1 end)

      assert Calculator.add(protomock, 1, 2) == -1
    end

    test "a stub is called after all expectations are fulfilled" do
      protomock =
        ProtoMock.new(StubOrderTest)
        |> ProtoMock.stub(&StubOrderTest.test/1, fn -> :stubbed end)
        |> ProtoMock.expect(&StubOrderTest.test/1, 3, fn -> :expected end)

      assert StubOrderTest.test(protomock) == :expected
      assert StubOrderTest.test(protomock) == :expected
      assert StubOrderTest.test(protomock) == :expected
      assert StubOrderTest.test(protomock) == :stubbed
      assert StubOrderTest.test(protomock) == :stubbed
    end

    test "overwrites earlier stubs" do
      protomock =
        ProtoMock.new(StubOrderTest)
        |> ProtoMock.stub(&StubOrderTest.test/1, fn -> :first end)
        |> ProtoMock.stub(&StubOrderTest.test/1, fn -> :second end)

      assert StubOrderTest.test(protomock) == :second
    end

    test "allows recursive calls" do
      protomock = ProtoMock.new(RecursiveTest)

      protomock
      |> ProtoMock.stub(&RecursiveTest.countdown/2, fn
        0 -> [0]
        i -> [i | RecursiveTest.countdown(protomock, i - 1)]
      end)

      assert RecursiveTest.countdown(protomock, 3) == [3, 2, 1, 0]
    end

    test "verifies that the mocked function is a member function of a protocol implemented by ProtoMock" do
      protomock = ProtoMock.new(Calculator)

      assert_raise ArgumentError, ~r/not a function/, fn ->
        ProtoMock.stub(protomock, :not_a_function, fn -> nil end)
      end

      assert_raise ArgumentError, ~r/is not recognized/, fn ->
        ProtoMock.stub(protomock, &Map.new/0, fn -> nil end)
      end

      assert_raise ArgumentError, ~r/does not implement/, fn ->
        ProtoMock.stub(protomock, &Enumerable.count/1, fn -> nil end)
      end

      assert_raise ArgumentError, ~r/not a function exported by/, fn ->
        function = Function.capture(Calculator, :add, 4)
        ProtoMock.stub(protomock, function, fn -> nil end)
      end
    end
  end

  describe "invoke" do
    test "raises errors that the impl function raises in the client" do
      protomock =
        ProtoMock.new(Calculator)
        |> ProtoMock.stub(&Calculator.add/3, fn _x, _y -> raise "crash" end)

      assert_raise RuntimeError, "crash", fn -> Calculator.add(protomock, 1, 2) end
    end
  end

  describe "checking arity of implementation functions" do
    test "when the impl arity equals the arity of the mocked function" do
      assert_raise ArgumentError, ~r/equal to the arity/, fn ->
        ProtoMock.new(Calculator)
        |> ProtoMock.stub(&Calculator.add/3, fn 1, 2, 3 -> :error end)
      end

      assert_raise ArgumentError, ~r/equal to the arity/, fn ->
        ProtoMock.new(Calculator)
        |> ProtoMock.expect(&Calculator.add/3, fn 1, 2, 3 -> :error end)
      end
    end

    test "when the impl arity is completely unexpected" do
      assert_raise ArgumentError, ~r/expected arity/, fn ->
        ProtoMock.new(Calculator)
        |> ProtoMock.stub(&Calculator.add/3, fn 1, 2, 3, 4 -> :error end)
      end

      assert_raise ArgumentError, ~r/expected arity/, fn ->
        ProtoMock.new(Calculator)
        |> ProtoMock.expect(&Calculator.add/3, fn 1, 2, 3, 4 -> :error end)
      end
    end
  end

  describe "invoke with runtime type checks disabled" do
    test "does not raise for invalid return types" do
      protomock =
        ProtoMock.new(Calculator)
        |> ProtoMock.stub(&Calculator.add/3, fn _x, _y -> :invalid_return_type end)

      assert Calculator.add(protomock, 1, 2) == :invalid_return_type
    end

    test "does not raise for invalid argument types" do
      protomock =
        ProtoMock.new(Calculator)
        |> ProtoMock.stub(&Calculator.add/3, fn _x, _y -> 2 end)

      assert Calculator.add(protomock, 1, :invalid_argument) == 2
    end
  end

  describe "invoke with runtime type checks enabled" do
    test "raises when the implementation returns the wrong type" do
      assert_raise RuntimeError, fn ->
        protomock =
          ProtoMock.new(Calculator, nil, check_runtime_types: true)
          |> ProtoMock.stub(&Calculator.add/3, fn _x, _y -> :bad_return end)

        Calculator.add(protomock, 1, 2)
      end
    end

    test "raises when an argument has an invalid type" do
      assert_raise RuntimeError, fn ->
        protomock =
          ProtoMock.new(Calculator, nil, check_runtime_types: true)
          |> ProtoMock.stub(&Calculator.add/3, fn x, _y -> x end)

        Calculator.add(protomock, 1, :invalid_argument)
      end
    end

    test "does not raise when mocked function does not have a typespec" do
      protomock =
        ProtoMock.new(Calculator, nil, check_runtime_types: true)
        |> ProtoMock.stub(&Calculator.sqrt/2, fn _x -> "not a float" end)

      assert Calculator.sqrt(protomock, :not_a_float) == "not a float"
    end

    test "does not raise when the mocked protocol has no typespecs" do
      protomock =
        ProtoMock.new(NoTypespecs, nil, check_runtime_types: true)
        |> ProtoMock.stub(&NoTypespecs.do_something/2, fn x -> x end)

      assert NoTypespecs.do_something(protomock, 3) == 3
    end
  end

  describe "specifying a protocol with new()" do
    test "creates the impl if necessary" do
      defprotocol Hello do
        def hello(impl)
      end

      protomock =
        ProtoMock.new(Hello)
        |> ProtoMock.expect(&Hello.hello/1, fn -> "hello" end)

      assert Hello.hello(protomock) == "hello"
      assert ProtoMock.verify!(protomock) == :ok
    end

    test "ensures that stubbed functions are member functions of the mocked protocol" do
      protomock = ProtoMock.new(Calculator)

      assert ProtoMock.stub(protomock, &Calculator.add/3, fn _, _ -> nil end) == protomock

      assert_raise ArgumentError, fn ->
        ProtoMock.expect(protomock, &OtherProtocol.do_something/1, fn -> nil end)
      end
    end

    test "ensures that expectation functions are member functions of the mocked protocol" do
      protomock = ProtoMock.new(Calculator)

      assert ProtoMock.expect(protomock, &Calculator.add/3, fn _, _ -> nil end) == protomock

      assert_raise ArgumentError, fn ->
        ProtoMock.expect(protomock, &OtherProtocol.do_something/1, fn -> nil end)
      end
    end
  end

  describe "delegation" do
    test "when the delegate does not implement the protocol, it raises an error" do
      assert_raise ArgumentError, ~r/must implement/, fn ->
        ProtoMock.new(Calculator, :not_a_calculator)
      end
    end

    test "when the delegate is nil, it raises an error" do
      assert_raise ArgumentError, ~r/must not be nil/, fn ->
        ProtoMock.new(Calculator, nil)
      end
    end

    test "when a delegate is provided, it delgates function calls by default" do
      protomock =
        ProtoMock.new(Calculator, RealCalculator.new())

      assert Calculator.add(protomock, 1, 2) == 3
      assert Calculator.mult(protomock, 1, 2) == 2
      assert Calculator.sqrt(protomock, 4) == 2
    end

    test "when a function is stubbed, the stub is called instead of the delegate" do
      protomock =
        ProtoMock.new(Calculator, RealCalculator.new())
        |> ProtoMock.stub(&Calculator.add/3, fn _x, _y -> :not_delegated end)

      assert Calculator.add(protomock, 1, 2) == :not_delegated
      assert Calculator.mult(protomock, 1, 2) == 2
      assert Calculator.sqrt(protomock, 4) == 2
    end

    test "when expectations are set, the delegate is not called" do
      protomock =
        ProtoMock.new(Calculator, RealCalculator.new())
        |> ProtoMock.expect(&Calculator.add/3, fn _x, _y -> :not_delegated end)

      assert Calculator.add(protomock, 1, 2) == :not_delegated
      assert Calculator.mult(protomock, 1, 2) == 2
      assert Calculator.sqrt(protomock, 4) == 2
    end

    test "when expectations are met, verify! returns :ok" do
      protomock =
        ProtoMock.new(Calculator, RealCalculator.new())
        |> ProtoMock.expect(&Calculator.add/3, fn _x, _y -> :not_delegated end)

      assert Calculator.add(protomock, 1, 2) == :not_delegated
      assert ProtoMock.verify!(protomock) == :ok
    end

    test "when expectations are not met, verify! raises" do
      protomock =
        ProtoMock.new(Calculator, RealCalculator.new())
        |> ProtoMock.expect(&Calculator.add/3, fn _x, _y -> :not_delegated end)

        msg = "expected Calculator.add/3 to be called once but it was called 0 times"

        assert_raise VerificationError, msg, fn ->
          ProtoMock.verify!(protomock)
        end
    end

    test "after expectations are met, the stub is called if there is one" do
      protomock =
        ProtoMock.new(Calculator, RealCalculator.new())
        |> ProtoMock.expect(&Calculator.add/3, fn _x, _y -> :expected end)
        |> ProtoMock.stub(&Calculator.add/3, fn _x, _y -> :stubbed end)

      assert Calculator.add(protomock, 1, 2) == :expected
      assert Calculator.add(protomock, 1, 2) == :stubbed
    end

    test "if expectations are exceeded, it raises an error" do
      protomock =
        ProtoMock.new(Calculator, RealCalculator.new())
        |> ProtoMock.expect(&Calculator.add/3, fn _x, _y -> :not_delegated end)

      Calculator.add(protomock, 1, 2)

      msg = "expected Calculator.add/3 to be called once but it was called twice"

      assert_raise ProtoMock.UnexpectedCallError, msg, fn ->
        Calculator.add(protomock, 1, 2)
      end
    end
  end

  defp mock_add() do
    mock_add(ProtoMock.new(Calculator))
  end

  defp mock_add(protomock) do
    protomock |> ProtoMock.expect(&Calculator.add/3, fn x, y -> x + y end)
  end

  defp stub_add() do
    ProtoMock.new(Calculator)
    |> ProtoMock.stub(&Calculator.add/3, fn x, y -> x + y end)
  end
end

defprotocol NoTypespecs do
  def do_something(impl, x)
end

defprotocol StubOrderTest do
  def test(impl)
end

defprotocol RecursiveTest do
  def countdown(impl, number)
end

defprotocol OtherProtocol do
  def do_something(impl)
end
