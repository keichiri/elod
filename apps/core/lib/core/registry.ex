defmodule Core.Registry do
  @moduledoc """
  Serves as a central process registry.

  Simple key-based registry that offers lookup.
  Processes are either explicitly deregistered or they are deregistered when
  they terminate

  This is a placeholder for a more sophisticated solution.
  """

  defstruct processes: %{}, monitors: %{}

  use GenServer

  require Logger

  alias Core.Registry, as: Registry


  def start_link do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end


  def register(id, pid) do
    GenServer.cast(__MODULE__, {:register, id, pid})
  end

  def deregister(id) do
    GenServer.cast(__MODULE__, {:deregister, id})
  end

  def whereis(id) do
    GenServer.call(__MODULE__, {:whereis, id})
  end


  def init(_) do
    Logger.info "Starting registry"
    {:ok, %Registry{}}
  end


  def handle_cast({:register, id, pid}, state) do
    new_state = handle_register(state, id, pid)
    {:noreply, new_state}
  end

  def handle_cast({:deregister, id}, state) do
    new_state = handle_deregister(state, id)
    {:noreply, new_state}
  end


  def handle_call({:whereis, id}, _from, state) do
    reply = handle_whereis(state, id)
    {:reply, reply, state}
  end


  def handle_info({:'DOWN', monitor, :process, pid, reason}, state) do
    Logger.debug "Registry handling dead process. PID: #{inspect pid}. Reason: #{inspect reason}"
    new_state = handle_dead_process(state, monitor)
    {:noreply, new_state}
  end

  def handle_info(msg, state) do
    Logger.warn "Unexpected message arrived at registry. Content: #{inspect msg}"
    {:noreply, state}
  end


  defp handle_register(state = %{processes: processes, monitors: monitors}, id, pid) do
    if Process.alive?(pid) do
      monitor = Process.monitor(pid)
      new_processes = Map.put(processes, id, {pid, monitor})
      new_monitors = Map.put(monitors, monitor, id)
      Logger.debug "Registering pid: #{inspect pid} under id: #{inspect id}"
      %{state | processes: new_processes, monitors: new_monitors}
    else
      state
    end
  end


  defp handle_deregister(state = %{processes: processes, monitors: monitors}, id) do
    case Map.pop(processes, id) do
      {nil, _} ->
        state

      {{pid, monitor}, new_processes} ->
        Logger.debug "Deregistering pid: #{inspect pid} under id: #{inspect id}"
        Process.demonitor(monitor)
        new_monitors = Map.delete(monitors, monitor)
        %{state | processes: new_processes, monitors: new_monitors}
    end
  end


  defp handle_whereis(%{processes: processes}, id) do
    case Map.get(processes, id) do
      nil ->
        Logger.error "Invalid registry query for id: #{inspect id}"
        nil

      {pid, _} ->
        pid
    end
  end


  defp handle_dead_process(state = %{monitors: monitors, processes: processes}, monitor) do
    {id, new_monitors} = Map.pop(monitors, monitor)
    new_processes = Map.delete(processes, id)
    %{state | processes: new_processes, monitors: new_monitors}
  end
end
