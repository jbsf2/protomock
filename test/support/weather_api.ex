defprotocol MyApp.WeatherAPI do
  @type lat_long :: {float(), float()}
  @type api_result :: {:ok, integer()} | {:error, any()}

  @spec temperature(t(), lat_long()) :: api_result()
  def temperature(weather_api, lat_long)

  @spec humidity(t(), lat_long()) :: api_result()
  def humidity(weather_api, lat_long)
end

defmodule AcmeWeather.ApiConfig do
  defstruct []
end

defmodule AcmeWeather.Client do
  def get_temperature(_lat, _long, _config), do: 0
  def get_humidity(_lat, _long, _config), do: 0
end

defimpl MyApp.WeatherAPI, for: AcmeWeather.ApiConfig do
  def temperature(api_config, {lat, long}) do
    AcmeWeather.Client.get_temperature(lat, long, api_config)
  end

  def humidity(api_config, {lat, long}) do
    AcmeWeather.Client.get_humidity(lat, long, api_config)
  end
end

defimpl MyApp.WeatherAPI, for: ProtoMock do
  def temperature(protomock, lat_long) do
    ProtoMock.invoke(protomock, &MyApp.WeatherAPI.temperature/2, [lat_long])
  end

  def humidity(protomock, lat_long) do
    ProtoMock.invoke(protomock, &MyApp.WeatherAPI.humidity/2, [lat_long])
  end
end

# ProtoMock.create_impl(MyApp.WeatherAPI)

defmodule MyApp.HumanizedWeather do
  alias MyApp.WeatherAPI

  def display_temp({lat, long}, weather_api \\ default_weather_api()) do
    {:ok, temp} = WeatherAPI.temperature(weather_api, {lat, long})
    "Current temperature is #{temp} degrees"
  end

  def display_humidity({lat, long}, weather_api \\ default_weather_api()) do
    {:ok, humidity} = WeatherAPI.humidity(weather_api, {lat, long})
    "Current humidity is #{humidity}%"
  end

  defp default_weather_api() do
    Application.get_env(MyApp, :weather_api)
  end
end
