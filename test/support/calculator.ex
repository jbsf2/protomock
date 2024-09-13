defprotocol Calculator do
  @spec add(t(), integer(), integer()) :: integer()
  def add(calculator, x, y)

  @spec mult(t(), integer(), integer()) :: integer()
  def mult(calculator, x, y)

  def sqrt(calulator, x)
end

defmodule RealCalculator do
  defstruct []

  @type t :: %__MODULE__{}

  def new() do
    %__MODULE__{}
  end

  defimpl Calculator do
    def add(_impl, x, y) do
      x + y
    end
    def mult(_impl, x, y) do
      x * y
    end
    def sqrt(_impl, x) do
      :math.sqrt(x)
    end
  end
end
