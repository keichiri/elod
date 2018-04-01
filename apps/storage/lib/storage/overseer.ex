defmodule Storage.Overseer do
  defstruct base: nil, active_directories: %{}
  use GenServer

  require Logger


  def start_link(base) do
    GenServer.start_link(__MODULE__, [base], name: __MODULE__)
  end

  def activate_directory(info_hash, dir_name) do
    GenServer.call(__MODULE__, {:activate_directory, info_hash, dir_name})
  end

  def deactivate_directory(info_hash) do
    GenServer.call(__MODULE__, {:deactivate_directory, info_hash})
  end


  def init(base) do
    try do
      File.ls!(base)
    catch _err, reason ->
      Logger.error("Failed to access base: #{inspect base}. Reason: #{inspect reason}")
      exit(reason)
    end
    {:ok, %Storage.Overseer{base: base}}
  end


  def handle_call(
    {:activate_directory, info_hash, dir_name}, _from,
    state = %{base: base, active_directories: active}
  ) do
    if Map.has_key?(active, info_hash) do
      Logger.warn("Denied activating directory #{inspect dir_name}. Already active")
      {:reply, {:error, :already_active}, state}
    else
      Logger.info("Activating directory #{inspect dir_name}. Info hash: #{inspect info_hash}")
      new_active = Map.put(active, info_hash, dir_name)
      path = Path.join(base, dir_name)
      Storage.DirectoriesSupervisor.activate_directory(info_hash, path)
      {:reply, :ok, %{state | active_directories: new_active}}
    end
  end


  def handle_call(
    {:deactivate_directory, info_hash},
    state = %{active_directories: active}
  ) do
    case Map.get(active, info_hash) do
      nil ->
        Logger.warn("Denied deactivating directory. No registered directory for #{info_hash}")
        {:reply, {:error, :no_active_directory}, state}

      dir_name ->
        Logger.info("Deactivating directory #{inspect dir_name}")
        Storage.DirectoriesSupervisor.deactivate_directory(info_hash)
        new_active = Map.delete(active, info_hash)
        {:reply, :ok, %{state | active_directories: new_active}}
    end
  end
end
