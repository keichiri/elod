defmodule Storage.WorkerSupervisor do
  use Supervisor

  require Logger


  def start_link(path) do
    Supervisor.start_link(__MODULE__, [path])
  end

  def start_worker(pid, worker_id) do
    Supervisor.start_child(pid, [worker_id])
  end

  def terminate_child(supervisor_pid, worker_pid) do
    Supervisor.terminate_child(supervisor_pid, worker_pid)
  end

  def init([path]) do
    Core.Registry.register({:storage, :worker_supervisor, path}, self())
    child_spec = [
      worker(Storage.Worker, [path])
    ]
    supervise(child_spec, strategy: :simple_one_for_one)
  end
end
