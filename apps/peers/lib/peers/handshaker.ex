defmodule Peers.Handshaker do
  @moduledoc """
  Handshaker is responsible for coordinating the Peer Wire Protocol handshakes,
  both as the initiating side (where the input is peer's ip and port and info hash) and as
  the acceptor (where the input is socket and peer's ip)

  New connections are initiated from PeerCoordinator. Incoming connections are
  coming from Server's side, once new connection has been accepted.

  Its main job is to ensure the acts of receiving, decoding and validating remote peer's
  handshake as well as encoding and sending local peer's handshake.
  Once handshake is successful, and the given info hash is validated (meaning the
  download is active for given info hash), the socket is handed off to PeerCoordinator
  for further communication.

  The actual work is performed in Worker module, one process per handshaking.
  """

  defstruct coordinators: %{}, initiators: %{}, receivers: %{}, peer_id: nil

  use GenServer

  require Logger

  alias Peers.Handshaker, as: Handshaker
  alias Peers.Handshaker.Worker, as: Worker

  @handshake_destination Application.get_env(:peers, :peer_coordinator)


  def start_link(peer_id) do
    GenServer.start_link(__MODULE__, peer_id, name: __MODULE__)
  end


  @doc """
  Called by PeerCoordinator during their initialization process.
  This is a synchronous call.

  NOTE - an alternative would be to resolve info hashes using registry instead
  of having them explicitly register with Handshaker.
  """
  def register(info_hash, pid) do
    GenServer.call(__MODULE__, {:register, info_hash, pid})
  end


  @doc """
  Called by PeerCoordinator during their termination.

  NOTE - handshaker is not linked nor does it monitor peer coordinators.
  """
  def deregister(info_hash) do
    GenServer.call(__MODULE__, {:deregister, info_hash})
  end


  @doc """
  Called by PeerCoordinator in order to when a new PWP conversation with remote
  peer is to be initiated, meaning that the handshakes must be exchanged.

  PeerCoordinator is assumed to be registered until this point, so once the handshake
  has been completed, it will be sent to pid provided during registration process.

  NOTE - this means that handshake initiation cannot "survive" PeerCoordinator's
  restart. Can be improved
  """
  def initiate(remote_peer_ip, remote_peer_port, info_hash) do
    GenServer.cast(__MODULE__, {:initiate, remote_peer_ip, remote_peer_port, info_hash})
  end


  @doc """
  Called by Server once a new connection has been accepted. At this point only
  its IP is know, and handshake receival process should begin.
  """
  def handle_incoming_connection(socket, remote_peer_ip) do
    pid = Process.whereis(__MODULE__)
    :gen_tcp.controlling_process(socket, pid)
    GenServer.cast(pid, {:incoming_connection, socket, remote_peer_ip})
  end


  @doc """
  Called by Worker if a handshake initiation has completed successfully.
  Makes sure socket ownership is transferred to Handshaker.
  """
  def handle_initiate_success(worker_pid, remote_id, socket) do
    :gen_tcp.controlling_process(socket, Process.whereis(__MODULE__))
    GenServer.cast(__MODULE__, {:initiate_success, worker_pid, remote_id, socket})
  end

  @doc """
  Called by Worker if a handshake initiation has completed unsuccessfully.
  """
  def handle_initiate_failure(worker_pid, reason) do
    GenServer.cast(__MODULE__, {:initiate_failure, worker_pid, reason})
  end


  @doc """
  Called by Worker during handshake receival process, in order to check whether
  given info hash received in handshake from peer is active (registered by coordinator)
  """
  def check_info_hash(info_hash) do
    GenServer.call(__MODULE__, {:check_info_hash, info_hash})
  end


  @doc """
  Called by Worker if a handshake receival has completed successfully.
  """
  def handle_receive_success(worker_pid, remote_peer_id, info_hash) do
    GenServer.cast(__MODULE__, {:receive_success, worker_pid, remote_peer_id, info_hash})
  end


  @doc """
  Called by Worker if a handshake receival has completed unsuccessfully.
  """
  def handle_receive_failure(worker_pid, err) do
    GenServer.cast(__MODULE__, {:receive_failure, worker_pid, err})
  end


  def init(peer_id) do
    Logger.info "Starting handshaker. Peer id: #{peer_id}"
    Process.flag(:trap_exit, true)
    state = %Handshaker{
      peer_id: peer_id
    }
    {:ok, state}
  end


  def handle_cast({:initiate, remote_ip, remote_port, info_hash}, state) do
    new_state = process_initiate(state, remote_ip, remote_port, info_hash)
    {:noreply, new_state}
  end

  def handle_cast({:initiate_success, worker_pid, remote_id, socket}, state) do
    new_state = process_initiate_success(state, worker_pid, remote_id, socket)
    {:noreply, new_state}
  end

  def handle_cast({:initiate_failure, worker_pid, reason}, state) do
    new_state = process_initiate_failure(state, worker_pid, reason)
    {:noreply, new_state}
  end

  def handle_cast({:incoming_connection, socket, remote_ip}, state) do
    new_state = process_incoming_connection(state, socket, remote_ip)
    {:noreply, new_state}
  end

  def handle_cast({:receive_success, worker_pid, remote_peer_id, info_hash}, state) do
    new_state = process_receive_success(state, worker_pid, remote_peer_id, info_hash)
    {:noreply, new_state}
  end

  def handle_cast({:receive_failure, worker_pid, error}, state) do
    new_state = process_receive_failure(state, worker_pid, error)
    {:noreply, new_state}
  end


  def handle_call({:register, info_hash, pid}, _from, state = %{coordinators: coordinators}) do
    Logger.debug "Registering controller for info hash: #{info_hash}"
    new_coordinators = Map.put(coordinators, info_hash, pid)
    {:reply, :ok, %{state | coordinators: new_coordinators}}
  end

  def handle_call({:deregister, info_hash}, _from, state = %{coordinators: coordinators}) do
    Logger.debug "Deregistering controller for info hash: #{info_hash}"
    new_coordinators = Map.delete(coordinators, info_hash)
    {:reply, :ok, %{state | coordinators: new_coordinators}}
  end

  def handle_call({:check_info_hash, info_hash}, _from, state = %{coordinators: coordinators}) do
    {:reply, Map.has_key?(coordinators, info_hash), state}
  end


  def handle_info({:'EXIT', _, :normal}, state) do
    {:noreply, state}
  end
  def handle_info({:'EXIT', pid, reason}, state) do
    new_state = handle_exit(state, pid, reason)
    {:noreply, new_state}
  end

  def handle_info(msg, state) do
    Logger.error "Unexpected message to handshaker: #{inspect msg}"
    {:noreply, state}
  end


  defp process_initiate(
    state = %{peer_id: peer_id, initiators: initiators},
    remote_ip, remote_port, info_hash
  ) do
    Logger.debug "Starting handshake initiate process with ip: #{inspect remote_ip}"
    worker_pid = Worker.initiate(remote_ip, remote_port, info_hash, peer_id)
    new_initiators = Map.put(initiators, worker_pid, {remote_ip, info_hash})
    %{state | initiators: new_initiators}
  end


  defp process_initiate_success(
    state = %{coordinators: coordinators, initiators: initiators},
    worker_pid, remote_id, socket
  ) do
    {{remote_ip, info_hash}, new_initiators} = Map.pop(initiators, worker_pid)
    Logger.debug "Successfully initiated handshake with ip: #{inspect remote_ip}"
    coordinator_pid = Map.get(coordinators, info_hash)

    if coordinator_pid do
      @handshake_destination.process_initiate_success(coordinator_pid, remote_ip, remote_id, socket)
    else
      Logger.error "Coordinator deregistered while handshake initiated. Resolve this properly"
      :gen_tcp.close(socket)
    end

    %{state | initiators: new_initiators}
  end


  defp process_initiate_failure(
    state = %{coordinators: coordinators, initiators: initiators},
    worker_pid, reason
  ) do
    {{remote_ip, info_hash}, new_initiators} = Map.pop(initiators, worker_pid)
    Logger.warn "Failed to initiate handshake with: #{inspect remote_ip}. Reason: #{inspect reason}"
    coordinator_pid = Map.get(coordinators, info_hash)

    if coordinator_pid do
      @handshake_destination.process_initiate_failure(coordinator_pid, remote_ip)
    else
      Logger.error "Coordinator deregistered while handshake initiated. Resolve this properly"
    end

    %{state | initiators: new_initiators}
  end


  defp process_incoming_connection(
    state = %{peer_id: peer_id, receivers: receivers},
    socket, remote_ip
  ) do
    Logger.debug "Starting handshake receival process with ip: #{inspect remote_ip}"
    worker_pid = Worker.receive(socket, peer_id)
    new_receivers = Map.put(receivers, worker_pid, {socket, remote_ip})
    %{state | receivers: new_receivers}
  end

  defp process_receive_success(
    state = %{receivers: receivers, coordinators: coordinators},
    worker_pid, remote_peer_id, info_hash
  ) do
    {{socket, remote_ip}, new_recievers} = Map.pop(receivers, worker_pid)
    Logger.debug "Received valid handshake from ip: #{inspect remote_ip}. Calling coordinator"
    coordinator_pid = Map.get(coordinators, info_hash)

    if coordinator_pid do
      @handshake_destination.process_receive_success(coordinator_pid, remote_ip, remote_peer_id, socket)
    else
      :gen_tcp.close(socket)
      Logger.error "Coordinator deregistered while handshake received. Resolve this properly"
    end

    %{state | receivers: new_recievers}
  end

  defp process_receive_failure(
    state = %{receivers: receivers},
    worker_pid, err
  ) do
    {{socket, remote_ip}, new_receivers} = Map.pop(receivers, worker_pid)
    Logger.warn "Receiving handshake from: #{inspect remote_ip} failed. Reason: #{inspect err}"
    :gen_tcp.close(socket)
    %{state | receivers: new_receivers}
  end


  defp handle_exit(
    state = %{receivers: receivers},
    pid, reason
  ) do
    if Map.has_key?(receivers, pid) do
      process_receive_failure(state, pid, reason)
    else
      process_initiate_failure(state, pid, reason)
    end
  end
end


defmodule Peers.Handshaker.Worker do
  @moduledoc """
  Worker is responsible for performing the actual handshake, spawned by and
  reporting its outcome to Handshaker

  Can be spawned both as a handshake initiator and receiver.
  """

  alias Peers.Handshaker, as: Handshaker
  alias Peers.PWP, as: PWP

  require Logger

  @connect_timeout 5000
  @receive_timeout 5000
  @send_timeout 5000
  @connect_opts [:binary, active: :false, send_timeout: @send_timeout]


  @doc """
  Called by Handshaker in order to perform the work of initiating handshake.

  Upon the execution completion, Worker will call the appropriate Handshaker's
  function.
  """
  def initiate(remote_ip, remote_port, info_hash, peer_id) do
    spawn_link(
      __MODULE__,
      :initiate_handshake,
      [remote_ip, remote_port, info_hash, peer_id]
    )
  end


  @doc """
  Called by Handshaker in order to perform the work of receiving handshake.

  Socket is assumed to be in passive state, so no transfer control needs to occur.

  Upon the execution completion, Worker will call the appropriate Handshaker's
  function.
  """
  def receive(socket, peer_id) do
    spawn_link(
      __MODULE__,
      :receive_handshake,
      [socket, peer_id]
    )
  end


  def initiate_handshake(remote_ip, remote_port, info_hash, peer_id) do
    case :gen_tcp.connect(remote_ip, remote_port, @connect_opts, @connect_timeout) do
      {:ok, socket} ->
        case exchange_handshakes_as_initiator(socket, info_hash, peer_id) do
          {:ok, remote_peer_id} ->
            Handshaker.handle_initiate_success(self(), remote_peer_id, socket)

          err ->
            :gen_tcp.close(socket)
            Handshaker.handle_initiate_failure(self(), err)
        end

      err ->
        Handshaker.handle_initiate_failure(self(), err)
    end
  end

  defp exchange_handshakes_as_initiator(socket, info_hash, peer_id) do
    out_handshake = PWP.encode_handshake(info_hash, peer_id)
    with :ok <- :gen_tcp.send(socket, out_handshake),
         {:ok, data} <- :gen_tcp.recv(socket, 0, @receive_timeout),
         {:ok, {^info_hash, remote_peer_id}} <- PWP.decode_handshake(data) do
      {:ok, remote_peer_id}
    else
      {:ok, {_bad_info_hash, _peer_id}} -> {:error, :bad_info_hash}
      err -> err
    end
  end


  def receive_handshake(socket, peer_id) do
    case exchange_handshakes_as_receiver(socket, peer_id) do
      {:ok, remote_peer_id, info_hash} ->
        Handshaker.handle_receive_success(self(), remote_peer_id, info_hash)

      err ->
        Handshaker.handle_receive_failure(self(), err)
    end
  end

  def exchange_handshakes_as_receiver(socket, peer_id) do
    with {:ok, data} <- :gen_tcp.recv(socket, 0, @receive_timeout),
         {:ok, {info_hash, remote_peer_id}} <- PWP.decode_handshake(data),
         true <- verify_info_hash(info_hash),
         handshake_data = PWP.encode_handshake(info_hash, peer_id),
         :ok <- :gen_tcp.send(socket, handshake_data) do
      {:ok, remote_peer_id, info_hash}
    end
  end

  defp verify_info_hash(info_hash) do
    Handshaker.check_info_hash(info_hash)
  end
end
