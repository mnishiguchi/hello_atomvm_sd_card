defmodule SampleApp do
  @moduledoc """
  Minimal SD card demo on AtomVM.

  Boot flow:
  - Start SPI bus owner
  - Mount /sdcard (FAT) via sdspi
  - List directory entries
  - Periodically re-print directory listing
  - Sleep forever
  """

  @compile {:no_warn_undefined, :gpio}
  @compile {:no_warn_undefined, :atomvm}

  alias SampleApp.{
    Buses.SPI,
    Storage.SDCard
  }

  @spi_config Application.compile_env!(:sample_app, :spi_config)
  @pin_sd_cs Application.compile_env!(:sample_app, :sd_cs_pin)

  @sd_driver ~c"sdspi"
  @sd_root ~c"/sdcard"

  # Re-print interval so you can attach picocom later and still see logs
  @status_interval_ms 10_000

  ## AtomVM entrypoint (mix.exs atomvm.start points here)

  def start() do
    {:ok, _pid} = start_link()

    # Keep the VM alive
    Process.sleep(:infinity)
  end

  def start_link(opts \\ []) do
    :gen_server.start_link({:local, __MODULE__}, __MODULE__, :ok, opts)
  end

  ## gen_server callbacks

  def init(:ok) do
    IO.puts("Starting demo (SD card directory listing)")

    {:ok, _} = SPI.start_link(@spi_config)

    # Keep SD CS de-selected unless mounting/reading.
    :gpio.set_pin_mode(@pin_sd_cs, :output)
    :gpio.digital_write(@pin_sd_cs, :high)

    case SPI.transaction(fn spi ->
           :io.format(~c"Mounting SD card (root=~s, driver=~s, cs=~p)~n", [
             @sd_root,
             @sd_driver,
             @pin_sd_cs
           ])

           case SDCard.mount(spi, @pin_sd_cs, @sd_root, @sd_driver) do
             {:ok, _mref} ->
               SDCard.print_directory(@sd_root)
               :ok

             {:error, reason} ->
               :io.format(~c"SD card mount failed (~p)~n", [reason])
               {:error, reason}
           end
         end) do
      {:ok, _} ->
        :ok

      {:error, e} ->
        :io.format(~c"SPI transaction failed: ~p~n", [e])
    end

    IO.puts("Ready (will re-print directory periodically)")

    # Kick off periodic status prints
    Process.send_after(self(), :status, @status_interval_ms)

    {:ok, %{}}
  end

  def handle_info(:status, state) do
    _ =
      case SPI.transaction(fn _spi ->
             SDCard.print_directory(@sd_root)
           end) do
        {:ok, _} ->
          :ok

        {:error, e} ->
          :io.format(~c"status print failed: ~p~n", [e])
      end

    # Reschedule
    Process.send_after(self(), :status, @status_interval_ms)

    {:noreply, state}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  def terminate(_reason, _state), do: :ok
end
