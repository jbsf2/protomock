defprotocol Calculator do
  @spec add(t(), integer(), integer()) :: integer()
  def add(calculator, x, y)

  @spec mult(t(), integer(), integer()) :: integer()
  def mult(calculator, x, y)

  @spec sqrt(t(), float()) :: float()
  def sqrt(calulator, x)

  @spec rand(t()) :: float()
  def rand(calculator)
end

defimpl Calculator, for: ProtoMock do
  def add(protomock, x, y) do
    ProtoMock.invoke(protomock, &Calculator.add/3, [protomock, x, y])
  end

  def mult(protomock, x, y) do
    ProtoMock.invoke(protomock, &Calculator.mult/3, [protomock, x, y])
  end

  def sqrt(protomock, x) do
    ProtoMock.invoke(protomock, &Calculator.sqrt/2, [protomock, x])
  end

  def rand(protomock) do
    ProtoMock.invoke(protomock, &Calculator.rand/1, [protomock])
  end
end
