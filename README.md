# ProtoMock

<!-- MDOC -->
<!-- INCLUDE -->

ProtoMock is a library for mocking Elixir protocols.

## Motivation / use case

ProtoMock was built to support using protocols, rather than behaviours and/or plain
modules, for modeling and accessing external APIs. When external APIs are modeled with
protocols, ProtoMock can provide mocking capabilities.

Modeling external APIs with protocols provides these benefits:

* API transparency
* IDE navigability
* Compiler / dialyzer error detection
* Flexible options for mocking (for example using fake objects for some tests, instead of a mocking library)

It is not expected that ProtoMock would be useful for more traditional protocol use
cases, wherein protocols such as `Enumerable` provide a common interface for operating on
disparate data structures. In such situations, there is no value in testing with mocks,
therefore ProtoMock has no role.

## Getting started

Add `protomock` to your list of dependencies in `mix.exs`:

    def deps do
      [
        # ...
        {:protomock, "~> 0.2.0", only: :test}
      ]
    end

Because ProtoMock generates implementations of the protocols that it mocks, we need to
disable [protocol consolidation](https://hexdocs.pm/elixir/1.15.6/Protocol.html#module-consolidation) for the `:test` environment in `mix.exs`:

    def project do
      [
        # ...
        consolidate_protocols: Mix.env() != :test
      ]
    end

To enable [Hammox](https://hexdocs.pm/hammox/Hammox.html)-style [runtime type checking](`enable_type_checking/0`), add this to your `test_helper.exs` or 
equivalent:
  
      ProtoMock.enable_type_checking()

## Example

Following the traditional [Mox example](https://hexdocs.pm/mox/Mox.html#module-example),
imagine that we have an app that displays the weather. To retrieve weather data,
we use an external weather API called AcmeWeather, and we model the API with our own
protocol:

    defprotocol MyApp.WeatherAPI do
      @type lat_long :: {float(), float()}
      @type api_result :: {:ok, float()} | {:error, String.t()}

      @spec temperature(t(), lat_long()) :: api_result()
      def temperature(weather_api, lat_long)

      @spec humidity(t(), lat_long()) :: api_result()
      def humidity(weather_api, lat_long)
    end

We create a "real" implementation of `WeatherAPI` that calls out to the
AcmeWeather API client:

    defimpl MyApp.WeatherAPI, for: AcmeWeather.ApiConfig do
      def temperature(api_config, {lat, long}) do
        AcmeWeather.Client.get_temperature(lat, long, api_config)
      end

      def humidity(api_config, {lat, long}) do
        AcmeWeather.Client.get_humidity(lat, long, api_config)
      end
    end

For testing, however, we want to mock the service.

Continuing with the [Mox example](https://hexdocs.pm/mox/Mox.html#module-example),
imagine that our application code looks like:

    defmodule MyApp.HumanizedWeather do
      alias MyApp.WeatherAPI

      def display_temp({lat, long}, weather_api) do
        {:ok, temp} = WeatherAPI.temperature(weather_api, {lat, long})
        "Current temperature is #{temp} degrees"
      end

      def display_humidity({lat, long}, weather_api) do
        {:ok, humidity} = WeatherAPI.humidity(weather_api, {lat, long})
        "Current humidity is #{humidity}%"
      end
    end

We can test `HumanizedWeather` by mocking `WeatherAPI` with ProtoMock:

    defmodule MyApp.HumanizedWeatherTest do
      use ExUnit.Case, async: true

      alias MyApp.HumanizedWeather
      alias MyApp.WeatherAPI

      test "gets and formats temperature" do
        protomock =
          ProtoMock.new(WeatherAPI)
          |> ProtoMock.expect(&WeatherAPI.temperature/2, 1, fn _lat_long -> {:ok, 30} end)

        assert HumanizedWeather.display_temp({50.06, 19.94}, protomock) ==
                "Current temperature is 30 degrees"

        ProtoMock.verify!(protomock)
      end

      test "gets and formats humidity" do
        protomock =
          ProtoMock.new(WeatherAPI)
          |> ProtoMock.stub(&WeatherAPI.humidity/2, fn _lat_long -> {:ok, 60} end)

        assert HumanizedWeather.display_humidity({50.06, 19.94}, protomock) ==
              "Current humidity is 60%"
      end
    end

In the first test, we use `expect/4` to declare that `WeatherAPI.temperature/2` should be called
exactly once. The expectation is verified via `verify!/1`.

In the second test, we use `stub/3`, which does not set expectations on the number of times
the mocked function should be called, therefore we do not need to verify.

## Under the hood: a GenServer

The `ProtoMock` module is a GenServer. Each time we create a `ProtoMock` with `new/1`,
we start a new `ProtoMock` GenServer that is linked to the calling process - typically
an ExUnit test process. When the test pid dies, the `ProtoMock` GenServer dies with it.

`expect/4` and `stub/3` modify the `ProtoMock` GenServer state to tell the `ProtoMock`
how it will be used and how it should respond. As the `ProtoMock` instance is used to
dispatch functions of a mocked protocol, it records each function invocation.
`verify!/1` compares the function invocations to the expectations defined via
`expect/4`, and raises in case of an expectations mismatch.

## Comparison to [Mox](https://hexdocs.pm/mox/Mox.html)

In order to feel familiar to developers, the ProtoMock API was modeled after the Mox API.

Some differences worth noting:

* ProtoMock has no concept of private mode or global mode. It's expected that each ExUnit
  test will create its own instance or instances of `ProtoMock` that are implicitly private
  to the test pid, thereby always being safe for `async: true`
* Similarly, ProtoMock has no concept of allowances. Each `ProtoMock` instance is just a
  GenServer that can be used freely and without worry by any process spawned by an
  ExUnit test process (provided that the child process does not interact with other tests).
* Rather than specificying expectations and stubs with a module name and a function name,
  e.g. `(MyAPIModule, :my_api_function ...)`, ProtoMock uses function captures, e.g.
  `&MyApiProtocol.my_api_function/2`. As a benefit, API mismatches between actual code and
  expectations/stubs will be flagged by the compiler.
* `stub_with` and `verify_on_exit` are not meaningful when using ProtoMock, and they
  are not implemented.

## Runtime type checking

ProtoMock supports runtime type checking of mocked functions, via code adopted from [Hammox](https://hexdocs.pm/hammox/Hammox.html).
Type checking is disabled by default. It can be enabled via `enable_type_checking/0`.
See `enable_type_checking/0` for details on how type checking works.

## Goals and philosophy

ProtoMock aims to support and enable the notion that each test should be its own
little parallel universe, without any modifiable state shared between tests. It
intentionally avoids practices common in mocking libraries such as setting/resetting
Application environment variables. Such practices create potential collisions between
tests that must be avoided with `async: false`. ProtoMock believes `async` should
always be `true`!

ProtoMock aims to provide an easy-on-the-eyes, function-oriented API that doesn't
rely on macros and doesn't require wrapping test code in closures.
