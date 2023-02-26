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

ProtoMock.defimpl(Calculator)
