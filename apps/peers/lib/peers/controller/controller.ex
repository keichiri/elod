defmodule Peers.Controller do
  @moduledoc """
  PeerController maintains a conversation with a remote peer.

  It sits on top of Channel which offers to him a nice API in term of PWP messages.
  PeerController is responsible for:
    1. ensuring PWP is not violated
    2. coordinating, requesting and receiving blocks that consist a piece
       assigned by PeerCoordinator
    3. asking for blocks to be retrieved to be sent to remote peer
    4. validating remote peer's piece requested by keeping copy of announced bitfield

  # NOTE - handles PWP violations by reporting to Coordinator,
  expecting to be told to stop later, instead of exiting early.
  """

  alias Peers.Controller.BlockHandler, as: BlockHandler
  alias Peers.Controller, as: Controller
  alias Peers.Channel, as: Channel
  alias Peers.Coordinator, as: Coordinator

  defstruct ip: nil,
            coordinator: nil,
            channel: nil,
            local_choke: true,
            remote_choke: true,
            local_interested: false,
            remote_interested: false,
            local_bitfield: <<>>,
            last_interested_ts: 0,
            block_handler: BlockHandler.new()

  use GenServer

  require Logger
  require Bitwise


  def start_link(ip, socket, coordinator) do
    {:ok, pid} = GenServer.start_link(__MODULE__, {ip, socket, coordinator})
    :gen_tcp.controlling_process(socket, pid)
    send(pid, :start)
    {:ok, pid}
  end


  def start_download(pid, piece) do
    GenServer.cast(pid, {:start_download, piece})
  end

  def choke(controller) do
    GenServer.cast(controller, :choke)
  end
  def unchoke(controller) do
    GenServer.cast(controller, :unchoke)
  end

  def announce_have(controller, index) do
    GenServer.cast(controller, {:announce_have, index})
  end

  def send_bitfield(controller, bitfield) do
    GenServer.cast(controller, {:send_bitfield, bitfield})
  end

  def cancel_piece(controller, index) do
    GenServer.cast(controller, {:cancel_piece, index})
  end

  def stop(controller) do
    GenServer.cast(controller, :stop)
  end


  @doc """
  Called by Channel (passed to it in a closure) whenever a new message arrives.
  """
  def handle_incoming_message(pid, message) do
    GenServer.cast(pid, {:incoming_message, message})
  end


  def init(args = {ip, _socket, _coordinator}) do
    Logger.debug "Starting PeerController for ip: #{inspect ip}"
    {:ok, args}
  end


  def handle_cast(:choke, state) do
    new_state = process_local_choke(state)
    {:noreply, new_state}
  end
  def handle_cast(:unchoke, state) do
    new_state = process_local_unchoke(state)
    {:noreply, new_state}
  end

  def handle_cast({:start_download, piece}, state) do
    new_state = process_start_download(state, piece)
    {:noreply, new_state}
  end

  def handle_cast({:announce_have, index}, state = %{channel: channel, bitfield: bitfield}) do
    Logger.debug "Announcing have to: #{inspect state.ip}"
    Channel.send_message(channel, {:have, index})
    new_bitfield = Core.Bitfield.add_index(bitfield, index)
    new_state = %{state | local_bitfield: new_bitfield}
    {:noreply, new_state}
  end

  def handle_cast({:send_bitfield, bitfield}, state = %{channel: channel}) do
    Logger.debug "Sending bitfield to: #{inspect state.ip}"
    Channel.send_message(channel, {:bitfield, bitfield})
    new_state = %{state | local_bitfield: bitfield}
    {:noreply, new_state}
  end

  def handle_cast({:cancel_piece, index}, state) do
    new_state = process_cancel(state, index)
    {:noreply, new_state}
  end

  def handle_cast(:stop, state) do
    Logger.debug "Stopping controller for: #{inspect state.ip}"
    {:stop, :normal, state}
  end

  def handle_cast({:incoming_message, message}, state) do
    new_state = process_incoming_message(state, message)
    {:noreply, new_state}
  end


  def handle_info(:start, {ip, socket, coordinator}) do
    pid = self()
    on_incoming_message = fn msg ->
      Controller.handle_incoming_message(pid, msg)
    end
    {:ok, channel} = Channel.start_link(socket, ip, on_incoming_message)
    state = %Controller{
      ip: ip,
      coordinator: coordinator,
      channel: channel,
    }
    {:noreply, state}
  end


  def terminate(reason, state = %{channel: channel}) do
    unless reason == :normal do
      Logger.error "Controller for: #{inspect state.ip} terminating. Reason: #{inspect reason}"
    end
    Channel.stop(channel)
    :ok
  end


  defp process_local_choke(state = %{channel: channel}) do
    Logger.debug "Choking Peer at #{inspect state.ip}"
    Channel.send_message(channel, :choke)
    %{state | local_choke: true}
  end

  defp process_local_unchoke(state = %{channel: channel}) do
    Logger.debug "Unchoking Peer at #{inspect state.ip}"
    Channel.send_message(channel, :unchoke)
    %{state | local_choke: false}
  end


  defp process_start_download(
    state = %{block_handler: block_handler},
    piece
  ) do
    new_block_handler = BlockHandler.add_piece(block_handler, piece)
    state = %{state | block_handler: new_block_handler, local_interested: true}
    attempt_to_progress_download(state)
  end

  defp attempt_to_progress_download(state = %{remote_choke: remote_choke}) do
    unless remote_choke do
      maybe_request_more(state)
    else
      maybe_send_interested(state)
    end
  end

  defp maybe_send_interested(state = %{remote_choke: true, last_interested_ts: ts}) do
    now = :os.system_time(:seconds)
    if now - ts > 60 do
      Logger.debug "Cannot request more. Sending interested message"
      Channel.send_message(state.channel, :interested)
      %{state | last_interested_ts: now}
    else
      Logger.debug "Cannot request more. Interested message sent recently."
      state
    end
  end

  defp maybe_request_more(state = %{block_handler: block_handler, channel: channel}) do
    {to_request, new_block_handler} = BlockHandler.schedule_blocks(block_handler)
    Logger.debug "Requesting #{length(to_request)} new pieces"
    Enum.each(to_request, fn %{index: index, offset: offset, length: length} ->
      Channel.send_message(channel, {:request, index, offset, length})
    end)
    %{state | block_handler: new_block_handler}
  end


  defp has_announced_piece(bitfield, index) do
    byte_pos = div(index, 8)
    byte_offset = rem(index, 8)
    value = String.at(bitfield, byte_pos)
    Bitwise.band(value, Bitwise.<<<(1, byte_offset)) > 0
  end


  defp process_cancel(state = %{block_handler: block_handler, channel: channel}, index) do
    {blocks_to_cancel, new_block_handler} = BlockHandler.cancel_piece(block_handler, index)
    Logger.debug "Canceling piece with index: #{index} with #{length(blocks_to_cancel)} requested blocks"
    Enum.each(blocks_to_cancel, fn %{index: index, offset: offset, length: length} ->
      Channel.send_message(channel, {:cancel, index, offset, length})
    end)
    %{state | block_handler: new_block_handler}
  end


  defp process_incoming_message(state = %{remote_choke: false}, :choke) do
    Logger.debug "Peer at #{inspect state.ip} started choking"
    Coordinator.handle_peer_choking(state.coordinator, state.ip)
    %{state | remote_choke: true}
  end
  defp process_incoming_message(state, :choke) do
    state
  end

  defp process_incoming_message(state = %{remote_choke: true}, :unchoke) do
    Logger.debug "Peer at #{inspect state.ip} stopped choking"
    Coordinator.handle_peer_unchoking(state.coordinator, state.ip)
    maybe_request_more(state)
  end
  defp process_incoming_message(state, :unchoke) do
    state
  end

  defp process_incoming_message(state = %{remote_interested: false}, :interested) do
    Logger.debug "Peer at #{inspect state.ip} interested"
    %{state | remote_interested: true}
  end
  defp process_incoming_message(state, :interested) do
    state
  end

  defp process_incoming_message(state = %{remote_interested: true}, :uninterested) do
    Logger.debug "Peer at #{inspect state.ip} uninterested"
    %{state | remote_interested: false}
  end
  defp process_incoming_message(state, :uninterested) do
    state
  end

  defp process_incoming_message(state = %{coordinator: coordinator}, {:have, index}) do
    Logger.debug "Peer at #{inspect state.ip} announced possession of index: #{index}"
    Coordinator.handle_announced_piece(coordinator, state.ip, index)
    state
  end

  defp process_incoming_message(
    state = %{coordinator: coordinator, bitfield: nil},
    {:bitfield, bitfield}
  ) do
    Logger.debug "Peer at #{inspect state.ip} sent bitfield"
    Coordinator.handle_bitfield(coordinator, state.ip, bitfield)
    state
  end
  defp process_incoming_message(state = %{coordinator: coordinator}, {:bitfield, _bitfield}) do
    Logger.warn "PWP VIOLATION. Peer at #{inspect state.ip} sent bitfield again"
    Coordinator.handle_pwp_violation(coordinator, state.ip, :bitfield_repeat)
    state
  end

  defp process_incoming_message(
    state = %{coordinator: coordinator, local_choke: true},
    {:request, _index, _offset, _length}
  ) do
    Logger.warn "PWP VIOLATION. Peer at #{inspect state.ip} sending request while choked"
    Coordinator.handle_pwp_violation(coordinator, self(), :request_while_choked)
    state
  end
  defp process_incoming_message(
    state = %{local_bitfield: bitfield, coordinator: coordinator},
    {:request, index, offset, length}
  ) do
    if has_announced_piece(bitfield, index) do
      start_retrieval(state, index, offset, length)
    else
      Logger.warn "PWP VIOLATION. Peer at #{inspect state.ip} requested unannounced piece"
      Coordinator.handle_pwp_violation(coordinator, state.ip, :request_unannounced)
      state
    end
  end

  defp process_incoming_message(state, {:piece, index, offset, data}) do
    block = %Core.Block{index: index, offset: offset, data: data}
    process_incoming_block(state, block)
  end

  defp process_incoming_message(state, {:cancel, _index, _offset, _length}) do
    Logger.warn "IMPLEMENT CANCEL"
    state
  end


  defp start_retrieval(state, index, offset, length) do
    raise "NOT IMPLEMENTED"
  end


  defp process_incoming_block(
    state = %{block_handler: block_handler, coordinator: coordinator},
    block
  ) do
    case BlockHandler.add_downloaded_block(block_handler, block) do
      {:ok, new_block_handler} ->
        Logger.debug "Received block from peer at: #{inspect state.ip}"
        state = %{state | block_handler: new_block_handler}
        attempt_to_progress_download(state)

      {:ok, new_block_handler, completed_piece} ->
        Logger.debug "Completed piece from peer at: #{inspect state.ip}"
        process_downloaded_piece(coordinator, completed_piece)
        %{state | block_handler: new_block_handler}

      {:error, :block_not_requested} ->
        Logger.warn "PWP Violation. Peer at #{inspect state.ip} sent not requested block"
        Coordinator.handle_pwp_violation(coordinator, state.ip, :invalid_block_sent)
        state
    end
  end


  defp process_downloaded_piece(state, piece = %{data: data, hash: hash}) do
    data_hash = :crypto.hash(:sha, data)
    if hash == data_hash do
      Coordinator.handle_downloaded_piece(state.coordinator, state.ip, piece)
    else
      Logger.warn "PWP Violation. Peer sent invalid piece"
      Coordinator.handle_pwp_violation(state.coordinator, state.ip, :invalid_piece)
    end
  end
end
