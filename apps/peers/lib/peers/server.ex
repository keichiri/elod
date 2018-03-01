defmodule Peers.Server do
  @moduledoc """
  TCP server that accepts connections and hands them off to Handshaker.

  Right now, there is no additional logic here. Afterwards, if necessary,
  peer blacklisting can be integrated here, to remove the blacklisted peers
  as soon as possible
  """

  require Logger

  alias Peers.Handshaker, as: Handshaker


  @doc """
  Blocking operation. Since this is one of the crucial moments in setting up
  PWP client, it is simpler to have the return information straight away
  """
  def start_link(port) do
    case :gen_tcp.listen(port, [:binary, reuseaddr: :true, active: :false]) do
      {:ok, socket} ->
        Logger.info "Opened server socket at port: #{port}. Starting server process"
        pid = spawn_link(__MODULE__, :start, [socket])
        Process.register(pid, __MODULE__)
        :ok = :gen_tcp.controlling_process(socket, pid)
        {:ok, pid}

      err ->
        err
    end
  end


  def start(socket) do
    loop(socket)
  end


  def stop do
    Process.exit(Process.whereis(__MODULE__), :kill) 
  end


  defp loop(socket) do
    case :gen_tcp.accept(socket) do
      {:ok, new_socket} ->
        {:ok, {ip, _port}} = :inet.peername(new_socket)
        Logger.debug "Accepted connection from ip: #{inspect ip}. Handing off to handshaker"
        Handshaker.handle_incoming_connection(new_socket, ip)
        loop(socket)

      {:error, reason} ->
        Logger.error "Error while accepting connections: #{inspect reason}. Terminating server"
        :gen_tcp.close(socket)
    end
  end
end
