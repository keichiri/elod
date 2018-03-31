defmodule Peers.Coordinator do
  @moduledoc """
  Coordinates all peer-related activity for a single metafile download.

  It is the main synchronization point for different modules.

  Responsibilities:
    1. handling announced peer information
    2. initiating new PWP conversations
    3. accepting incoming PWP conversations
    4. coordinating PeerControllers


  # TODO - keeping track of initiated store piece requests, and periodically reinitiating
  """

  alias Peers.Coordinator, as: Coordinator
  alias Peers.Controller, as: Controller
  alias Peers.Handshaker, as: Handshaker
  alias Peers.Coordinator.AnnouncedPeersTracker, as: AnnouncedPeersTracker
  alias Peers.Coordinator.ActivePeersTracker, as: ActiveTracker
  alias Peers.Coordinator.HealthTracker, as: HealthTracker
  alias Peers.Coordinator.PieceTracker, as: PieceTracker
  alias Peers.Coordinator.PieceAssigner, as: Assigner
  alias Core.Cache, as: Cache


  defstruct info_hash: nil,
            active: nil,
            download_coordinator: nil,
            piece_tracker: nil,
            requests: %{},
            controllers: %{},
            health_tracker: HealthTracker.new(),
            announced_tracker: AnnouncedPeersTracker.new(),
            cache: Cache.new(1024 * 1024 * 50),
            assigner: Assigner.new(100, 10, 10) # TODO

  require Logger

  use GenServer


  @max_initiate 10
  @max_accept 10


  def start_link(info_hash, pieces, download_coordinator) do
    GenServer.start_link(__MODULE__, {info_hash, pieces, download_coordinator})
  end


  @doc """
  Called by announcers each time an announcement has been made.

  Needs to find appropriate coordinator and deliver the result.
  """
  def handle_announce_result(info_hash, result) do
    id = {:peers_coordinator, info_hash}
    pid = Core.Registry.whereis(id)
    GenServer.cast(pid, {:announce_result, result})
  end


  @doc """
  Called by Handshaker once a new peer is incoming, and has successfully handshook.
  """
  def handle_receive_success(pid, ip, peer_id, socket) do
    :gen_tcp.controlling_process(socket, pid)
    GenServer.cast(pid, {:receive_success, ip, peer_id, socket})
  end


  @doc """
  Called by Handshaker if an initiation process terminated successfully.
  """
  def handle_initiate_success(pid, ip, peer_id, socket) do
    :gen_tcp.controlling_process(socket, pid)
    GenServer.cast(pid, {:initiate_success, ip, peer_id, socket})
  end


  @doc """
  Called by Handshaker if an initiation process terminated poorly.
  """
  def handle_initiate_failure(pid, ip) do
    GenServer.cast(pid, {:initiate_failure, ip})
  end

  @doc """
  Called by Controller if a remote peer started choking.
  """
  def handle_peer_choking(pid, ip) do
    GenServer.cast(pid, {:peer_choking, ip})
  end

  @doc """
  Called by Controller if a remote peer stopped choking.
  """
  def handle_peer_unchoking(pid, ip) do
    GenServer.cast(pid, {:peer_unchoking, ip})
  end

  @doc """
  Called by Controller when remote peer sends have message.
  """
  def handle_announced_piece(pid, ip, index) do
    GenServer.cast(pid, {:announced_piece, ip, index})
  end

  @doc """
  Called by Controller when peer sends its bitfield (it might not be the first tiem)
  """
  def handle_bitfield(pid, ip, index) do
    GenServer.cast(pid, {:bitfield, ip, index})
  end

  @doc """
  Called by Controller whenever PWP violation occurs. It is left to Coordinator
  to decide whether the communication should be terminated.
  """
  def handle_pwp_violation(pid, ip, reason) do
    GenServer.cast(pid, {:pwp_violation, ip, reason})
  end

  @doc """
  Called by Controller when a piece is successfully completed.
  """
  def handle_downloaded_piece(pid, ip, piece) do
    GenServer.cast(pid, {:downloaded_piece, ip, piece})
  end

  @doc """
  Callback given to Storage to be called when piece is stored. (or error happened)
  """
  def handle_store_piece_result(pid, index, res) do
    GenServer.cast(pid, {:piece_store_result, index, res})
  end


  @doc """
  Called by controller when it gets request message from unchoked peer.
  """
  def request_block(pid, ip, index, offset, length) do
    GenServer.cast(pid, {:request_block, ip, index, offset, length})
  end


  @doc """
  Callback given to Storage to be called when piece is retrieved. (or error happened)
  """
  def handle_piece_retrieval_result(pid, result) do
    GenServer.cast(pid, {:piece_retrieval_result, result})
  end


  def init({info_hash, pieces, download_coordinator}) do
    Logger.info "Starting Peer Coordinator for: #{info_hash}"
    existing_indexes = Storage.get_missing(info_hash) # TODO
    register(info_hash)
    state = %Coordinator{
      download_coordinator: download_coordinator,
      piece_tracker: PieceTracker.new(pieces, existing_indexes),
      info_hash: info_hash,
      active: ActiveTracker.new(@max_initiate, @max_accept)
    }
    {:ok, state}
  end


  def handle_cast(state, {:announce_result, result}) do
    new_state = process_announce_result(state, result)
    {:noreply, new_state}
  end

  def handle_cast(state, {:receive_success, ip, peer_id, socket}) do
    new_state = process_receive_success(state, ip, peer_id, socket)
    {:noreply, new_state}
  end

  def handle_cast(state, {:initiate_success, ip, peer_id, socket}) do
    new_state = process_initiate_success(state, ip, peer_id, socket)
    {:noreply, new_state}
  end

  def handle_cast(state, {:initiate_failure, ip}) do
    # TODO - more detailed logging
    Logger.warn "Received initiate failure report from Handshake for #{inspect ip}"
    {:noreply, state}
  end

  def handle_cast(state, {:peer_choking, ip}) do
    new_state = process_peer_choking(state, ip)
    {:noreply, new_state}
  end

  def handle_cast(state, {:peer_unchoking, ip}) do
    new_state = process_peer_unchoking(state, ip)
    {:noreply, new_state}
  end

  def handle_cast(state, {:announced_piece, ip, index}) do
    new_state = process_announced_piece(state, ip, index)
    {:noreply, new_state}
  end

  def handle_cast(state, {:bitfield, ip, bitfield}) do
    new_state = process_bitfield(state, ip, bitfield)
    {:noreply, new_state}
  end

  def handle_cast(state, {:pwp_violation, ip, reason}) do
    new_state = process_pwp_violation(state, ip, reason)
    {:noreply, new_state}
  end

  def handle_cast(state, {:downloaded_piece, ip, reason}) do
    new_state = process_downloaded_piece(state, ip, reason)
    {:noreply, new_state}
  end

  def handle_cast(state, {:piece_store_result, index, res}) do
    new_state = process_store_piece_result(state, index, res)
    {:noreply, new_state}
  end

  def handle_cast(state, {:request_block, ip, index, offset, length}) do
    new_state = process_block_request(state, ip, index, offset, length)
    {:noreply, new_state}
  end

  def handle_cast(state, {:piece_retrieval_result, res}) do
    new_state = process_piece_retrieval_result(state, res)
    {:noreply, new_state}
  end


  @doc """
  Updates announced tracker with announce result and optionally starts handshakes,
  if there is room. Does this unconditionally, even if there are no new peers in
  announced results and it is not possible to have new candidates, for simplicity sake
  """
  defp process_announce_result(
    state = %{announced: announced, active: active, info_hash: info_hash},
    {complete, incomplete, peers}
  ) do
    Logger.debug "Announce results for: #{state.info_hash}: #{complete} complete, #{incomplete} incomplete"
    announced = AnnouncedPeersTracker.process_announced_peers(announced, peers)
    room = ActiveTracker.get_initiation_room(active)

    if room > 0 do
      active_ips = ActiveTracker.get_active_ips(active)
      to_initiate =
        AnnouncedPeersTracker.get_candidates(announced, room)
        |> Enum.reject(&Enum.member?(active_ips, &1))
        |> Enum.shuffle
        |> Enum.take(room)
      Logger.debug "Has room: #{room}. Initiating #{length(to_initiate)} more"
      Enum.each(to_initiate, fn {ip, port} ->
        Handshaker.initiate(ip, port, info_hash)
      end)
    end

    %{state | announced: announced}
  end


  @doc """
  Needs to check whether remote peer is already active, if it already initiated
  or he was initiated upon!
  Also, needs to check whether the limit of accepted peers has been reached.

  In order to ensure good PWP behavior, once in a while, new peer should be
  accepted even if peers are full.
  Currently, this is done by removing one peer randomly.

  # TODO - move this decision about accepting earlier, let Handshaker call
  coordinator before answering handshake
  """
  defp process_receive_success(state = %{active_tracker: active}, ip, _peer_id, socket) do
    if not ActiveTracker.is_active?(active, ip) and ActiveTracker.can_accept?(active) do
      Logger.debug "Accepted #{inspect ip}. Starting controller"
      initiate_controller(state, ip, socket, :accepted)
    else
      unless ActiveTracker.has_recently_accepted?(active) do
        random_ip = ActiveTracker.pick_random_accepted(active)
        Logger.debug "Accepted #{inspect ip} after removing #{inspect random_ip}. Starting controller"
        state = terminate_peer(state, random_ip)
        initiate_controller(state, ip, socket, :accepted)
      else
        Logger.debug "Cannot accept #{inspect ip}. Closing connection"
        :gen_tcp.close(socket)
        state
      end
    end
  end


  @doc """
  Needs to check whether peer is active, meaning it got accepted during the handshake
  process. In that case, connection should be dropped.
  """
  defp process_initiate_success(state = %{active_tracker: active}, ip, _peer_id, socket) do
    unless ActiveTracker.is_active?(active, ip) do
      Logger.debug "Initiated #{inspect ip}. Starting new controller"
      initiate_controller(state, ip, socket, :initiated)
    else
      Logger.warn "Cannot add initiated #{inspect ip}. Already active. Closing connection"
      :gen_tcp.close(socket)
      state
    end
  end


  defp process_peer_choking(state = %{health_tracker: health_tracker}, ip) do
    %{state | health_tracker: HealthTracker.process_peer_choke(health_tracker, ip)}
  end

  defp process_peer_unchoking(state = %{health_tracker: health_tracker}, ip) do
    %{state | health_tracker: HealthTracker.process_peer_unchoke(health_tracker, ip)}
  end


  defp process_announced_piece(
    state = %{controllers: controllers, piece_tracker: piece_tracker, assigner: assigner},
    ip, piece_index
  ) do
    if PieceTracker.is_missing?(piece_tracker, piece_index) do
      piece_tracker = PieceTracker.update_with_index(piece_tracker, piece_index, ip)

      if Assigner.can_assign_more?(assigner, ip) do
        Logger.debug "Peer #{inspect ip} announced missing piece. Assigning"
        piece = PieceTracker.get_piece(piece_tracker, piece_index)
        controller_pid = Map.fetch!(controllers, ip)
        Controller.start_download(controller_pid, piece)
        %{state | tracker: piece_tracker,
                  assigner: Assigner.assign(assigner, piece_index, ip)}
      else
        Logger.debug "Peer #{inspect ip} announced missing piece, but cannot assign."
        %{state | tracker: piece_tracker}
      end
    else
      state
    end
  end


  defp process_bitfield(
    state = %{controllers: controllers, piece_tracker: piece_tracker, assigner: assigner},
    ip, bitfield
  ) do
    unless PieceTracker.has_possession_info?(piece_tracker, ip) do
      {indexes, piece_tracker} = PieceTracker.update_with_bitfield(piece_tracker, bitfield, ip)
      {assigned_indexes, assigner} = Assigner.assign_initial(assigner, indexes, ip)
      Logger.debug "Peer #{inspect ip} sent bitfield. Assigned #{length(assigned_indexes)} pieces"
      controller_pid = Map.fetch!(controllers, ip)

      Enum.each(assigned_indexes, fn index ->
        piece = PieceTracker.get_piece(piece_tracker, index)
        Controller.start_download(controller_pid, piece)
      end)
      %{state | piece_tracker: piece_tracker,
                assigner: assigner}
    else
      Logger.warn "Peer #{inspect ip} resent bitfield. Terminating"
      terminate_peer(state, ip)
    end
  end


  defp process_pwp_violation(state, ip, reason) do
    Logger.warn "Terminating peer: #{inspect ip} because of PWP violation: #{inspect reason}"
    terminate_peer(state, ip)
  end


  defp process_downloaded_piece(state, ip, piece = %{index: index}) do
    Logger.debug "Peer #{inspect ip} sent valid piece. Starting storing"
    pid = self()
    callback = fn res ->
      Coordinator.handle_store_piece_result(pid, index, res)
    end
    Storage.start_storing(state.info_hash, piece, callback)
    %{state | tracker: PieceTracker.mark_piece_as_storing(state.piece_tracker, piece, ip)}
  end


  defp process_store_piece_result(
    state = %{piece_tracker: piece_tracker, assigner: assigner, controllers: controllers},
    index, :ok
  ) do
    {original_downloader, piece_tracker} = PieceTracker.remove_storing_piece(piece_tracker, index)
    {all_downloaders, assigner} = Assigner.remove_piece(assigner, index)

    all_downloaders
    |> Stream.filter(&(&1 != original_downloader))
    |> Enum.each(fn ip ->
      pid = Map.fetch!(controllers, ip)
      Controller.cancel_piece(pid, index)
    end)

    # TODO - recheck this. Should have be sent to all the peers?
    controllers
    |> Stream.reject(fn {ip, _pid} -> Enum.member?(all_downloaders, ip) end)
    |> Enum.each(fn {_ip, pid} ->
      Controller.announce_have(pid, index)
    end)

    missing_count = PieceTracker.get_missing_count(piece_tracker)
    if missing_count == 0 do
      Logger.debug "Stored piece with index: #{inspect index}. Download completed"
      DownloadCoordinator.handle_all_stored(state.download_coordinator)
    else
      Logger.debug "Stored piece with index: #{inspect index}. Left: #{missing_count}"
    end

    %{state | piece_tracker: piece_tracker,
              assigner: assigner}
  end

  defp process_store_piece_result(state, index, err) do
    Logger.error "Failed to store piece swith index: #{index}. Error: #{inspect err}"
    pid = self()
    piece = PieceTracker.get_piece(state.piece_tracker, index)
    callback = fn res ->
      Coordinator.handle_store_piece_result(pid, index, res)
    end
    Storage.start_storing(state.info_hash, piece, callback)
    state
  end


  defp process_block_request(
    state = %{cache: cache, block_requests: requests},
    ip, index, offset, length
  ) do
    case Cache.get(cache, index) do
      nil ->
        new_requests = case Map.get(requests, index) do
          {list, ts} ->
            new_list = [{ip, offset, length} | list]
            # TODO - check if this is the best way to do this
            now = :os.system_time(:seconds)
            if now - ts > 3 do
              Storage.start_piece_retrieval(state.info_hash, index)
              Map.put(requests, index, {new_list,  now})
            else
              Map.put(requests, index, {new_list, ts})
            end

          nil ->
            start_piece_retrieval(state.info_hash, index)
            Map.put(requests, index, {[{ip, offset, length}], :os.system_time(:seconds)})
        end
        %{state | requests: new_requests}

      {data, new_cache} ->
        pid = Map.get(state.controllers, ip)
        # TODO - add stats
        Controller.send_block(pid, index, offset, String.slice(data, offset, length))
        %{state | cache: new_cache}
    end
  end

  defp start_piece_retrieval(info_hash, index) do
    pid = self()
    callback = fn res ->
      Coordinator.handle_piece_retrieval_result(pid, res)
    end
    Storage.start_piece_retrieval(info_hash, callback)
  end


  defp process_piece_retrieval_result(state, {:ok, index, data}) do
    {block_requests, new_requests} = Map.pop(state.requests, index)
    Enum.each(block_requests, fn {ip, offset, length} ->
      controller_pid = Map.get(state.controllers, ip)
      Controller.send_block(controller_pid, index, offset, String.slice(data, offset, length))
    end)
    %{state | requests: new_requests,
              cache: Cache.add(state.cache, index, data)}
  end

  defp process_piece_retrieval_result(state, {:error, index, reason}) do
    Logger.warn "Storage failed to retrieve piece. Reason: #{inspect reason}. Retrying"
    new_requests = Map.update!(state.requests, index, fn {block_requests, _ts} ->
      {block_requests, :os.system_time(:seconds)}
    end)
    start_piece_retrieval(state.info_hash, index)
    %{state | requests: new_requests}
  end


  defp initiate_controller(state, ip, socket, type) do
    pid = Controller.start_link(ip, socket, self())
    Controller.send_bitfield(pid, state.bitfield)
    new_active = case type do
      :initiated -> ActiveTracker.add_initiated(state.active_tracker, ip)
      :accepted -> ActiveTracker.add_accepted(state.active_tracker, ip)
    end
    %{state | controllers: Map.put(state.controllers, ip, pid),
              active_tracker: new_active,
              health_tracker: HealthTracker.add(state.health_tracker, ip)}
  end


  defp terminate_peer(state, ip) do
    controller_pid = Map.fetch!(state.controllers, ip)
    Controller.stop(controller_pid)
    %{state | controllers: Map.delete(state.controllers, ip),
              active_tracker: ActiveTracker.remove(state.active_tracker, ip),
              health_tracker: HealthTracker.remove(state.health_tracker, ip),
              piece_tracker: PieceTracker.remove_peer(state.piece_tracker, ip),
              assigner: Assigner.remove_peer(state.assigner, ip)}
  end


  defp register(info_hash) do
    id = {:peers_coordinator, info_hash}
    pid = self()
    Core.Registry.register(id, pid)
    Handshaker.register(info_hash, pid)
  end
end
