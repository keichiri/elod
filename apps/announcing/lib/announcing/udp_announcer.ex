defmodule Announcing.UDPAnnouncer do
  @moduledoc """
  Performs announcing to tracker using UDP.

  Announce process contains two steps:
    1. connect - simple UDP datagram exchange with the goal of obtaining connection id
    2. announce - sending UDP datagram containing announce parameter and receiving response
  """

  defstruct url: nil,
            host: nil,
            port: nil,
            socket: nil,
            dl_info: nil,
            next_announce: nil

  use GenServer

  require Logger

  alias Announcing.Announcer, as: Announcer
  alias Announcing.UDPAnnouncer, as: UDPAnnouncer

  @max_id 2147483647
  @receive_timeout 5000


  def start_link(url, download_info) do
    GenServer.start_link(__MODULE__, {url, download_info})
  end


  def init({url, dl_info}) do
    Process.flag(:trap_exit, true)
    Logger.info "Starting UDP announcer for URL: #{url}"
    Announcer.register(url)
    send(self(), :init)
    %URI{host: host, port: port} = URI.parse(url)
    host = case :inet.parse_ipv4_address(String.to_charlist(host)) do
      {:ok, ip} ->
         ip

      {:error, _} ->
        host
    end
    state = %UDPAnnouncer{
      url: url,
      host: host,
      port: port,
      dl_info: dl_info
    }
    {:ok, state}
  end


  def handle_cast(:announce_completion, state) do
    attempt_announce(state, "completed")
  end


  def handle_info(:init, state) do
    case :gen_udp.open(0) do
      {:ok, socket} ->
         :ok = :inet.setopts(socket, [:binary, active: :false])
         new_state = %{state | socket: socket}
         {:noreply, new_state, 0}

      {:error, reason} ->
        Logger.error "Failed to open UDP socket. Reason: #{reason}"
        {:stop, :failed_to_open_socket, state}
    end
  end


  def handle_info(:timeout, state = %{next_announce: next_announce}) do
    event = if next_announce do "" else "started" end
    attempt_announce(state, event)
  end


  def terminate(reason, state = %{url: url, next_announce: next_announce, socket: socket}) do
    unless reason == :normal do
      Logger.error "Announcer for URL: #{url} terminating because of: #{inspect reason}"
    end
    if next_announce do
      announce(state, "stopped")
    end
    :gen_tcp.close(socket)
    Announcer.deregister(url)
  end


  def attempt_announce(state, event) do
    case announce(state, event) do
      {:ok, tracker_response} ->
        new_state = process_tracker_response(state, tracker_response)
        sleep_time = Announcer.calculate_sleep_time(new_state.next_announce)
        {:noreply, new_state, sleep_time}

      {:error, reason} ->
        Logger.error "Failed to announce event #{event} to URL: #{state.url}. Error: #{inspect reason}"
        {:stop, :failed_announce, state}
    end
  end


  defp announce(state = %{host: host, port: port, socket: socket}, event) do
    case connection_step(socket, host, port) do
      {:ok, conn_id} ->
        IO.puts "Announcing event: #{event}"
        announce_step(state, socket, host, port, event, conn_id)

      err ->
        err
    end
  end


  defp connection_step(socket, host, port) do
    transaction_id = :rand.uniform(@max_id)
    connect_data = create_connect_request(transaction_id)

    with :ok <- :gen_udp.send(socket, host, port, connect_data),
         {:ok, {^host, _port, connect_response_data}} <- :gen_tcp.recv(socket, 16, @receive_timeout),
         {:ok, {^transaction_id, connection_id}} <- parse_connect_response(connect_response_data) do
      {:ok, connection_id}
    else
      {:ok, {_host, _port, _}} -> {:error, :bad_sender}
      {:ok, {_transation_id, _connection_id}} -> {:error, :bad_transaction_id}
      err -> err
    end
  end

  defp create_connect_request(transaction_id) do
    <<0x41727101980 :: integer-big-size(64),
      0 :: integer-big-size(32),
      transaction_id :: integer-big-size(32)>>
  end

  defp parse_connect_response(<<
    0 :: integer-big-size(32),
    transaction_id :: integer-big-size(32),
    connection_id :: integer-big-size(64)
  >>) do
    {:ok, {transaction_id, connection_id}}
  end
  defp parse_connect_response(resp) when byte_size(resp) == 16 do
    {:error, :bad_connect_response_length}
  end
  defp parse_connect_response(_resp) do
    {:error, :invalid_connect_response}
  end


  defp announce_step(state, socket, host, port, event, conn_id) do
    params = collect_params(state, event)
    transaction_id = :rand.uniform(@max_id)
    announce_data = create_announce_request(params, conn_id, transaction_id)

    with :ok <- :gen_udp.send(socket, host, port, announce_data),
         {:ok, {^host, _port, announce_response_data}} <- :gen_udp.recv(socket, 140, @receive_timeout),
         {:ok, {^transaction_id, tracker_response}} <- parse_announce_response(announce_response_data) do
      {:ok, tracker_response}
    else
      {:ok, {_host, _port, _}} -> {:error, :bad_sender}
      {:ok, {_transaction_id, _response}} -> {:error, :bad_transaction_id}
      err -> err
    end
  end

  defp collect_params(%{dl_info: dl_info}, event) do
    event_id = case event do
      "" -> 0
      "completed" -> 1
      "started" -> 2
      "stopped" -> 3
    end
    Stats.get(dl_info.info_hash)
    |> Map.merge(dl_info)
    |> Map.put(:event, event_id)
    |> Map.put(:numwant, 20)
    |> Map.put(:key, 19584)
  end

  defp create_announce_request(%{
    info_hash: info_hash,
    peer_id: peer_id,
    downloaded: downloaded,
    left: left,
    uploaded: uploaded,
    event: event,
    numwant: numwant,
    key: key,
    port: port
  }, connection_id, transaction_id) do
    <<connection_id :: big-integer-size(64),
      1 :: big-integer-size(32),
      transaction_id :: big-integer-size(32),
      info_hash :: bytes-size(20),
      peer_id :: bytes-size(20),
      downloaded :: big-integer-size(64),
      left :: big-integer-size(64),
      uploaded :: big-integer-size(64),
      event :: big-integer-size(32),
      0 :: big-integer-size(32), # IP
      key :: big-integer-size(32), # KEY
      numwant :: big-integer-size(32),
      port :: big-integer-size(16)>>
  end

  defp parse_announce_response(<<
    1 :: integer-big-size(32),
    transaction_id :: integer-big-size(32),
    interval :: integer-big-size(32),
    incomplete :: integer-big-size(32),
    complete :: integer-big-size(32),
    peer_data :: binary
  >>) when rem(byte_size(peer_data), 6) == 0 do
    {:ok, {transaction_id, {interval, {complete, incomplete, peer_data}}}}
  end
  defp parse_announce_response(_), do: {:error, :invalid_announce_response}


  defp process_tracker_response(state, {interval, peer_data}) do
    Logger.debug "Tracker for URL: #{state.url} gave interval: #{interval} and peer data: #{inspect peer_data}"
    Announcer.report_peer_data(state.dl_info, peer_data)
    next_announce = :os.system_time(:seconds) + interval
    new_state = %{state | next_announce: next_announce}
  end
end
