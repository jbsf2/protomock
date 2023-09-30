defprotocol Calculator do
  @spec add(t(), integer(), integer()) :: integer()
  def add(calculator, x, y)

  @spec mult(t(), integer(), integer()) :: integer()
  def mult(calculator, x, y)

  def sqrt(calulator, x)
end

ProtoMock.create_impl(Calculator)
