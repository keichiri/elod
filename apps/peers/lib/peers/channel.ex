defmodule Peers.Channel do
  @moduledoc """
  Channel is a layer on top of TCP, providing simpler abstraction that "speaks"
  PWP.

  It is intended to be a layer below PeerController, offering simple API for
  sending and receiving messages.
  Interface to PeerController is intended to be synchronous from controller's side,
  by invoking send(pid, message) and stop(). For incoming messages, a callback
  provided by the PeerController is to be called. This reduces coupling.

  NOTE - Channels are not meant to be restarted. During the channel process termination,
  socket should be closed properly.

  TODO - think about the error handling. Right now channel simply logs and dies
  when it encounters anomaly. It is up to PeerController to report this to PeerCoordinator.
  """

  defstruct socket: nil, ip: nil, on_incoming_message: nil, buffer: <<>>

  use GenServer

  require Logger

  alias Peers.Channel, as: Channel
  alias Peers.PWP, as: PWP


  @doc """
  Called once a handshake has been performed successfully and PWP conversation
  should proceed.

  At this point, socket is still in passive state. Its ownership should be transferred
  to newly spawned process

  ## Parameters:
    - socket: socket that was used during handshake process
    - ip: ip of the remote peer. For convenience, it could also be got from socket
    - on_incoming_message: function that is to be executed for each message
  """
  def start_link(socket, ip, on_incoming_message) do
    {:ok, pid} = GenServer.start_link(__MODULE__, {socket, ip, on_incoming_message})
    :ok = :gen_tcp.controlling_process(socket, pid)
    Process.flag(:trap_exit, true)
    send(pid, :start)
    {:ok, pid}
  end


  @doc """
  Schedules a message to be sent to remote peer.
  Message is in its unencoded shape.
  """
  def send_message(pid, message) do
    GenServer.cast(pid, {:send, message})
  end


  def stop(pid) do
    GenServer.cast(:stop, pid)
  end


  def init({socket, ip, on_incoming_message}) do
    Logger.debug "Starting channel to ip: #{inspect ip}"
    state = %Channel{
      socket: socket,
      ip: ip,
      on_incoming_message: on_incoming_message,
    }
    {:ok, state}
  end


  def handle_cast({:send, message}, state) do
    case send_pwp_message(state, message) do
      :ok ->
        {:noreply, state}

      err ->
        {:stop, err, state}
    end
  end

  def handle_cast(:stop, state) do
    {:stop, :normal, state}
  end


  def handle_info(:start, state = %{socket: socket}) do
    Logger.debug "Socket ownership transfer completed. Channel to ip: #{inspect state.ip} ready"
    :ok = :inet.setopts(socket, [:binary, active: :true])
    {:noreply, state}
  end

  def handle_info({:tcp, socket, message_content}, state = %{socket: socket}) do
    case process_incoming(state, message_content) do
      {:ok, new_state} ->
        {:noreply, new_state}

      err ->
        {:stop, err, state}
    end
  end
  def handle_info({:tcp_closed, _socket}, state) do
    {:stop, :tcp_closed, state}
  end

  def handle_info(msg, state) do
    Logger.error "Unexpected message to channel: #{inspect msg}"
    {:noreply, state}
  end


  def terminate(reason, %{socket: socket, ip: ip}) do
    if reason == :normal do
      Logger.debug "Terminating channel to ip: #{inspect ip} normally"
    else
      Logger.warn "Channel to ip: #{inspect ip} terminated unexpectedly. Reason: #{inspect reason}"
    end
    :gen_tcp.close(socket)
    :ok
  end


  defp send_pwp_message(%{socket: socket, ip: ip}, message) do
    content = PWP.encode(message)
    :ok = :gen_tcp.send(socket, content)
    Logger.debug "Sent #{inspect message} to ip: #{inspect ip}"
  end


  defp process_incoming(state = %{buffer: buffer, on_incoming_message: fun}, content) do
    total_binary = buffer <> content
    case PWP.decode_messages(total_binary) do
      {:ok, messages, remaining} ->
        if length(messages) != 0 do
          Logger.debug "Received #{length(messages)} messages from: #{inspect state.ip}"
          Enum.each(messages, fn msg -> fun.(msg) end)
        else
          Logger.debug "Received content. Buffer size: #{byte_size(remaining)} from: #{inspect state.ip}"
        end
        {:ok, %{state | buffer: remaining}}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
