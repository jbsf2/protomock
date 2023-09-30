defmodule MyApp.HumanizedWeatherTest do
  use ExUnit.Case, async: true

  alias MyApp.HumanizedWeather
  alias MyApp.WeatherAPI

  test "gets and formats temperature" do
    protomock =
      ProtoMock.new()
      |> ProtoMock.expect(&WeatherAPI.temperature/2, fn _lat_long -> {:ok, 30} end)

    assert HumanizedWeather.display_temp({50.06, 19.94}, protomock) ==
             "Current temperature is 30 degrees"

    ProtoMock.verify!(protomock)
  end

  test "gets and formats humidity" do
    protomock =
      ProtoMock.new()
      |> ProtoMock.stub(&WeatherAPI.humidity/2, fn _lat_long -> {:ok, 60} end)

    assert HumanizedWeather.display_humidity({50.06, 19.94}, protomock) ==
             "Current humidity is 60%"
  end
end
