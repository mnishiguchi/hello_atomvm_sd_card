import Config

# Hardware pins (ESP32-S3 GPIO numbers)
#
# This project is often used with the custom "Piyopiyo PCB" breakout board for XIAO-ESP32S3:
#   https://github.com/piyopiyoex/piyopiyo-pcb
#
# If you are using the Piyopiyo PCB, you can optionally set:
#
#   export PIYOPIYO_BOARD=v1.6
#
# Then SDCard CS is selected automatically:
# - v1.5 or lower  -> GPIO4
# - v1.6 or higher -> GPIO43
#
# If you're not using the Piyopiyo PCB, ignore PIYOPIYO_BOARD and just edit the pins below.

spi_config = [
  bus_config: [sclk: 7, miso: 8, mosi: 9],
  device_config: []
]

default_sd_cs_pin = 43

sd_cs_pin =
  case System.get_env("PIYOPIYO_BOARD") do
    nil ->
      default_sd_cs_pin

    "" ->
      default_sd_cs_pin

    board ->
      raise_invalid_board = fn ->
        raise """
        Unsupported PIYOPIYO_BOARD=#{inspect(board)}.

        Expected a version-like value such as:
          - "v1.5"
          - "v1.6"
          - "1.5"
          - "1.6.1"
        """
      end

      parts =
        board
        |> String.trim()
        |> String.trim_leading("v")
        |> String.split(".")

      parts =
        case parts do
          [maj] -> [maj, "0", "0"]
          [maj, min] -> [maj, min, "0"]
          [maj, min, patch] -> [maj, min, patch]
          _ -> :error
        end

      if parts == :error or not Enum.all?(parts, &String.match?(&1, ~r/^\d+$/)) do
        raise_invalid_board.()
      end

      version = parts |> Enum.join(".") |> Version.parse!()

      case Version.compare(version, Version.parse!("1.6.0")) do
        :lt -> 4
        _ -> 43
      end
  end

config :sample_app,
  spi_config: spi_config,
  sd_cs_pin: sd_cs_pin
