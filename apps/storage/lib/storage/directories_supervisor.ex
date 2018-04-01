defmodule Storage.DirectoriesSupervisor do
  use Supervisor

  require Logger


  def start_link do
    Supervisor.start_link(__MODULE__, [], name: __MODULE__)
  end


  def activate_directory(info_hash, path) do
    Supervisor.start_child(__MODULE__, [info_hash, path])
  end

  def deactivate_directory(info_hash) do
    pid = Core.Registry.whereis({:storage, :directory_supervisor, info_hash})
    Supervisor.terminate_child(__MODULE__, pid)
  end


  def init(_) do
    spec = [
      worker(Storage.DirectorySupervisor, [])
    ]
    supervise(spec, strategy: :simple_one_for_one)
  end
end
