defprotocol Calculator do

  @spec add(t(), integer(), integer()) :: integer()
  def add(calculator, int1, int2)

  @spec mult(t(), integer(), integer()) :: integer()
  def mult(calculator, int1, int2)

  @spec sqrt(t(), float()) :: float()
  def sqrt(calulator, num)
end

defimpl Calculator, for: ProtoMock do
  def add(protomock, int1, int2) do
    ProtoMock.invoke(protomock, &Calculator.add/3, [int1, int2])
  end

  def mult(protomock, int1, int2) do
    ProtoMock.invoke(protomock, &Calculator.mult/3, [int1, int2])
  end

  def sqrt(protomock, float) do
    ProtoMock.invoke(protomock, &Calculator.sqrt/2, [float])
  end
end
