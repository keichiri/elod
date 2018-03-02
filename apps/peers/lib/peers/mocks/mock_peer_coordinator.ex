defmodule Peers.Mock.MockPeerCoordinator do
  def start_link do
    pid = spawn_link(__MODULE__, :start, [])
    Process.register(pid, __MODULE__)
    pid
  end


  def process_initiate_success(pid, remote_ip, remote_id, _socket) do
    send(pid, {:initiate_success, remote_ip, remote_id})
  end

  def process_initiate_failure(pid, remote_ip) do
    send(pid, {:initiate_failure, remote_ip})
  end

  def process_receive_success(pid, remote_ip, remote_id, _socket) do
    send(pid, {:receive_success, remote_ip, remote_id})
  end

  def get_results do
    send(Process.whereis(__MODULE__), {:get, self()})
    receive do
      records ->
        {:ok, records}

    after 200 ->
      {:error, :no_response}
    end
  end


  def stop do
    Process.exit(__MODULE__, :kill)
  end


  def start do
    loop([])
  end



  defp loop(records) do
    receive do
      {:get, sender} ->
        send(sender, Enum.reverse(records))

      record ->
        loop([record | records])
    end
  end
end
