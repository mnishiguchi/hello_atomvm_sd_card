defmodule SampleApp.Storage.SDCard do
  @moduledoc """
  SD card helpers for AtomVM.

  - Paths are charlists (AtomVM POSIX expects flat charlists).
  - Keeps the mount ref reachable to avoid GC-related unmount issues.
  - Directory listing via AtomVM POSIX APIs.
  """

  @compile {:no_warn_undefined, :esp}
  @compile {:no_warn_undefined, :atomvm}

  alias SampleApp.AtomVMCompat

  @spec mount(term(), non_neg_integer(), charlist() | binary(), charlist()) ::
          {:ok, term()} | {:error, term()}
  def mount(spi_host, cs_pin, root, driver \\ ~c"sdspi") do
    root = AtomVMCompat.ensure_charlist(root)

    case :esp.mount(driver, root, :fat, spi_host: spi_host, cs: cs_pin) do
      {:ok, mount_ref} ->
        _pid = spawn_link(fn -> keep_mount_alive(mount_ref) end)
        {:ok, mount_ref}

      {:error, reason} ->
        :io.format(~c"SDCard mount failed (root=~s): ~p~n", [root, reason])
        {:error, reason}
    end
  end

  @spec print_directory(charlist() | binary()) :: :ok | {:error, term()}
  def print_directory(path) do
    path = AtomVMCompat.ensure_charlist(path)
    :io.format(~c"Listing ~s~n", [path])

    case with_dir(path, fn dir -> print_entries(dir) end) do
      :ok ->
        :ok

      {:error, reason} ->
        :io.format(~c"opendir(~s) failed: ~p~n", [path, reason])
        {:error, reason}
    end
  end

  @spec stream_file_chunks(charlist() | binary(), pos_integer(), (binary() -> any())) ::
          {:ok, non_neg_integer()} | {:error, term()}
  def stream_file_chunks(path, chunk_bytes, consumer_fun)
      when is_integer(chunk_bytes) and chunk_bytes > 0 and is_function(consumer_fun, 1) do
    path = AtomVMCompat.ensure_charlist(path)

    with_open_readonly(path, fn fd ->
      stream_loop(fd, chunk_bytes, 0, consumer_fun)
    end)
  end

  ## Internals

  defp keep_mount_alive(mount_ref) do
    _ = mount_ref
    Process.sleep(:infinity)
  end

  defp with_dir(path, fun) when is_function(fun, 1) do
    case :atomvm.posix_opendir(path) do
      {:ok, dir} ->
        try do
          fun.(dir)
        after
          :atomvm.posix_closedir(dir)
        end

      {:error, reason} ->
        {:error, reason}

      other ->
        {:error, other}
    end
  end

  defp with_open_readonly(path, fun) when is_function(fun, 1) do
    case :atomvm.posix_open(path, [:o_rdonly]) do
      {:ok, fd} ->
        try do
          fun.(fd)
        after
          :atomvm.posix_close(fd)
        end

      {:error, reason} ->
        :io.format(~c"open(~s) failed: ~p~n", [path, reason])
        {:error, reason}
    end
  end

  defp print_entries(dir) do
    case :atomvm.posix_readdir(dir) do
      {:ok, {:dirent, _ino, name0}} ->
        name = AtomVMCompat.normalize_name(name0)
        if name != [], do: :io.format(~c"  - ~s~n", [name])
        print_entries(dir)

      :eof ->
        :ok

      {:error, reason} ->
        :io.format(~c"readdir error: ~p~n", [reason])
        :ok

      _ ->
        :ok
    end
  end

  defp stream_loop(fd, chunk_bytes, total, consumer_fun) do
    case :atomvm.posix_read(fd, chunk_bytes) do
      {:ok, bin} when is_binary(bin) and bin != <<>> ->
        _ = consumer_fun.(bin)
        stream_loop(fd, chunk_bytes, total + byte_size(bin), consumer_fun)

      :eof ->
        {:ok, total}

      {:error, reason} ->
        :io.format(~c"read error: ~p~n", [reason])
        {:error, reason}

      _ ->
        {:ok, total}
    end
  end
end
