defmodule Storage.Supervisor do
  use Supervisor


  def start_link(base) do
    Supervisor.start_link(__MODULE__, [base], name: __MODULE__)
  end


  def init([base]) do
    spec = [
      worker(Storage.Overseer, [base]),
      supervisor(Storage.DirectoriesSupervisor, [])
    ]
    supervise(spec, strategy: :one_for_one)
  end
end
