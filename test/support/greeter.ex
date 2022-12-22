defprotocol Greeter do

  @spec greet(t(), String.t()) :: String.t()
  def greet(greeter, greetee)
end

defmodule English do
  defstruct []

  defimpl Greeter do
    def greet(_greeter, greetee) do
      "Hello, #{greetee}"
    end
  end
end

defmodule FakeGreeter do
  defstruct [:protomock]

  defimpl Greeter do
    def greet(greeter, greetee) do
      ProtoMock.respond(greeter.protomock, &Greeter.greet/2, [greetee])
    end
  end
end
