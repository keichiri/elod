defmodule Storage.DirectorySupervisor do
  use Supervisor

  require Logger


  def start_link(info_hash, path) do
    Supervisor.start_link(__MODULE__, [info_hash, path])
  end


  def init([info_hash, path]) do
    Logger.info "Starting directory supervisor for path: #{inspect path}"
    spec = [
      supervisor(Storage.WorkerSupervisor, [path]),
      worker(Storage.DirectoryHandler, [info_hash, path]),
    ]
    Core.Registry.register({:storage, :directory_supervisor, info_hash}, self())
    supervise(spec, strategy: :one_for_all)
  end
end
