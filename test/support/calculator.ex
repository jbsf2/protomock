defprotocol Calculator do
  @spec add(t(), integer(), integer()) :: integer()
  def add(calculator, x, y)

  @spec mult(t(), integer(), integer()) :: integer()
  def mult(calculator, x, y)

  @spec sqrt(t(), float()) :: float()
  def sqrt(calulator, x)
end

defimpl Calculator, for: ProtoMock do
  def add(protomock, x, y) do
    ProtoMock.invoke(protomock, &Calculator.add/3, [x, y])
  end

  def mult(protomock, x, y) do
    ProtoMock.invoke(protomock, &Calculator.mult/3, [x, y])
  end

  def sqrt(protomock, x) do
    ProtoMock.invoke(protomock, &Calculator.sqrt/2, [x])
  end
end
