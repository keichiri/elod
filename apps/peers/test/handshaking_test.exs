defmodule Peers.Test.Handshaking do
  use ExUnit.Case


  alias Peers.Server, as: Server
  alias Peers.Handshaker, as: Handshaker
  alias Peers.PWP, as: PWP
  alias Peers.Test.Handshaking.IncomingPeer, as: IncomingPeer
  alias Peers.Test.Handshaking.ReceivingPeer, as: ReceivingPeer
  alias Peers.Mock.MockPeerCoordinator, as: MockPeerCoordinator

  @local_port 30000
  @local_peer_id "11111111111111111111"
  @info_hash "00000000000000000000"
  @local_handshake <<19, "BitTorrent protocol", 0,0,0,0,0,0,0,0, @info_hash :: binary, @local_peer_id :: binary>>
  @remote_port 40000


  @doc """
  Tests receival of a single peer - accepting incoming connection, performing
  the handshake as a receiving side, and notifying the appropriate entity, which
  is MockPeerCoordinator. In real world, this will be PeerCoordinator.
  """
  test "receiving single peer" do
    {:ok, _} = Server.start_link(@local_port)
    {:ok, _} = Handshaker.start_link(@local_peer_id)
    valid_remote_peer_id = "99999999999999999999"
    remote_handshake = PWP.encode_handshake(@info_hash, valid_remote_peer_id)
    destination_pid = MockPeerCoordinator.start_link
    Handshaker.register(@info_hash, destination_pid)

    incoming_pid = IncomingPeer.start_link(@local_port, remote_handshake)

    :timer.sleep(100)

    sent_handshake = IncomingPeer.get_received_handshake(incoming_pid)
    {:ok, receiver_results} = MockPeerCoordinator.get_results

    assert receiver_results == [
      {:receive_success, {127,0,0,1}, valid_remote_peer_id}
    ]
    assert sent_handshake == @local_handshake
    Server.stop
  end


  @doc """
  Tests receival of a single peer which sends invalid handshake.

  Asserts that MockPeerCoordinator has not been called
  """
  test "receiving single peer - invalid handshake length" do
    {:ok, _} = Server.start_link(@local_port)
    {:ok, _} = Handshaker.start_link(@local_peer_id)
    valid_remote_peer_id = "99999999999999999999"
    remote_handshake = PWP.encode_handshake(@info_hash, valid_remote_peer_id) <> "0"
    destination_pid = MockPeerCoordinator.start_link
    Handshaker.register(@info_hash, destination_pid)

    incoming_pid = IncomingPeer.start_link(@local_port, remote_handshake)

    :timer.sleep(100)

    sent_handshake = IncomingPeer.get_received_handshake(incoming_pid)
    {:ok, receiver_results} = MockPeerCoordinator.get_results

    assert receiver_results == []
    assert sent_handshake == nil
    Server.stop
  end


  @doc """
  Tests receival of a single peer which sends invalid handshake.

  Asserts that MockPeerCoordinator has not been called
  """
  test "receiving single peer - no such info hash length" do
    {:ok, _} = Server.start_link(@local_port)
    {:ok, _} = Handshaker.start_link(@local_peer_id)
    valid_remote_peer_id = "99999999999999999999"
    invalid_info_hash = "00000000000000000001"
    remote_handshake = PWP.encode_handshake(invalid_info_hash, valid_remote_peer_id)
    destination_pid = MockPeerCoordinator.start_link
    Handshaker.register(@info_hash, destination_pid)

    incoming_pid = IncomingPeer.start_link(@local_port, remote_handshake)

    :timer.sleep(100)

    sent_handshake = IncomingPeer.get_received_handshake(incoming_pid)
    {:ok, receiver_results} = MockPeerCoordinator.get_results

    assert receiver_results == []
    assert sent_handshake == nil
    Server.stop
  end


  @doc """
  Tests receival of a several different peers.

  Asserts that the MockPeerCoordinators has received successes for all of the peers
  """
  test "receiving multiple peers" do
    {:ok, _} = Server.start_link(@local_port)
    {:ok, _} = Handshaker.start_link(@local_peer_id)
    valid_remote_peer_id_1 = "99999999999999999990"
    valid_remote_peer_id_2 = "99999999999999999991"
    valid_remote_peer_id_3 = "99999999999999999992"
    valid_remote_peer_id_4 = "99999999999999999993"
    valid_remote_peer_id_5 = "99999999999999999994"

    remote_handshake_1 = PWP.encode_handshake(@info_hash, valid_remote_peer_id_1)
    remote_handshake_2 = PWP.encode_handshake(@info_hash, valid_remote_peer_id_2)
    remote_handshake_3 = PWP.encode_handshake(@info_hash, valid_remote_peer_id_3)
    remote_handshake_4 = PWP.encode_handshake(@info_hash, valid_remote_peer_id_4)
    remote_handshake_5 = PWP.encode_handshake(@info_hash, valid_remote_peer_id_5)

    destination_pid = MockPeerCoordinator.start_link
    Handshaker.register(@info_hash, destination_pid)

    incoming_pid_1 = IncomingPeer.start_link(@local_port, remote_handshake_1)
    incoming_pid_2 = IncomingPeer.start_link(@local_port, remote_handshake_2)
    incoming_pid_3 = IncomingPeer.start_link(@local_port, remote_handshake_3)
    incoming_pid_4 = IncomingPeer.start_link(@local_port, remote_handshake_4)
    incoming_pid_5 = IncomingPeer.start_link(@local_port, remote_handshake_5)

    :timer.sleep(200)

    sent_handshake_1 = IncomingPeer.get_received_handshake(incoming_pid_1)
    sent_handshake_2 = IncomingPeer.get_received_handshake(incoming_pid_2)
    sent_handshake_3 = IncomingPeer.get_received_handshake(incoming_pid_3)
    sent_handshake_4 = IncomingPeer.get_received_handshake(incoming_pid_4)
    sent_handshake_5 = IncomingPeer.get_received_handshake(incoming_pid_5)
    assert sent_handshake_1 == @local_handshake
    assert sent_handshake_2 == @local_handshake
    assert sent_handshake_3 == @local_handshake
    assert sent_handshake_4 == @local_handshake
    assert sent_handshake_5 == @local_handshake

    {:ok, receiver_results} = MockPeerCoordinator.get_results
    sorted_results = Enum.sort(receiver_results, fn {_, _, id1}, {_, _, id2} ->
      id1 <= id2
    end)
    assert sorted_results == [
      {:receive_success, {127,0,0,1}, valid_remote_peer_id_1},
      {:receive_success, {127,0,0,1}, valid_remote_peer_id_2},
      {:receive_success, {127,0,0,1}, valid_remote_peer_id_3},
      {:receive_success, {127,0,0,1}, valid_remote_peer_id_4},
      {:receive_success, {127,0,0,1}, valid_remote_peer_id_5}
    ]
    Server.stop
  end


  @doc """
  Sets up a mock process that represents a single peer. Asserts that the handshake
  is sent to the remote peer properly, and that the handshake initiation outcome
  is reported to MockPeerCoordinator properly
  """
  test "initiating to a single peer" do
    {:ok, _} = Handshaker.start_link(@local_peer_id)
    valid_remote_peer_id = "99999999999999999999"
    remote_handshake = PWP.encode_handshake(@info_hash, valid_remote_peer_id)
    destination_pid = MockPeerCoordinator.start_link
    Handshaker.register(@info_hash, destination_pid)

    receiving_pid = ReceivingPeer.start_link(@remote_port, remote_handshake)
    Handshaker.initiate({127,0,0,1}, @remote_port, @info_hash)

    :timer.sleep(100)

    sent_handshake = ReceivingPeer.get_received_handshake(receiving_pid)
    {:ok, results} = MockPeerCoordinator.get_results

    assert results == [
      {:initiate_success, {127,0,0,1}, valid_remote_peer_id}
    ]
    assert sent_handshake == @local_handshake
  end

  @doc """
  Sets up a mock process that represents a single peer that responds with handshake
  of invalid length. Asserts that the handshake that  is sent to the remote peer properly,
  and that the handshake initiation outcome is reported to MockPeerCoordinator properly
  """
  test "initiating to a single peer - invalid handshake length" do
    {:ok, _} = Handshaker.start_link(@local_peer_id)
    valid_remote_peer_id = "99999999999999999999"
    remote_handshake = PWP.encode_handshake(@info_hash, valid_remote_peer_id) <> "0"
    destination_pid = MockPeerCoordinator.start_link
    Handshaker.register(@info_hash, destination_pid)

    receiving_pid = ReceivingPeer.start_link(@remote_port, remote_handshake)
    Handshaker.initiate({127,0,0,1}, @remote_port, @info_hash)

    :timer.sleep(100)

    sent_handshake = ReceivingPeer.get_received_handshake(receiving_pid)
    {:ok, results} = MockPeerCoordinator.get_results

    assert results == [
      {:initiate_failure, {127,0,0,1}}
    ]
    assert sent_handshake == @local_handshake
  end

  @doc """
  Sets up a mock process that represents a single peer that responds with handshake
  of invalid info hash. Asserts that the handshake that  is sent to the remote peer properly,
  and that the handshake initiation outcome is reported to MockPeerCoordinator properly
  """
  test "initiating to a single peer - invalid info hash" do
    {:ok, _} = Handshaker.start_link(@local_peer_id)
    valid_remote_peer_id = "99999999999999999999"
    remote_handshake = PWP.encode_handshake("12345123451234512345", valid_remote_peer_id)
    destination_pid = MockPeerCoordinator.start_link
    Handshaker.register(@info_hash, destination_pid)

    receiving_pid = ReceivingPeer.start_link(@remote_port, remote_handshake)
    Handshaker.initiate({127,0,0,1}, @remote_port, @info_hash)

    :timer.sleep(100)

    sent_handshake = ReceivingPeer.get_received_handshake(receiving_pid)
    {:ok, results} = MockPeerCoordinator.get_results

    assert results == [
      {:initiate_failure, {127,0,0,1}}
    ]
    assert sent_handshake == @local_handshake
  end


  @doc """
  Tests receival of a several different peers.

  Asserts that the MockPeerCoordinators has received successes for all of the peers
  """
  test "initiating multiple peers" do
    {:ok, _} = Handshaker.start_link(@local_peer_id)
    valid_remote_peer_id_1 = "99999999999999999990"
    valid_remote_peer_id_2 = "99999999999999999991"
    valid_remote_peer_id_3 = "99999999999999999992"
    valid_remote_peer_id_4 = "99999999999999999993"
    valid_remote_peer_id_5 = "99999999999999999994"

    remote_handshake_1 = PWP.encode_handshake(@info_hash, valid_remote_peer_id_1)
    remote_handshake_2 = PWP.encode_handshake(@info_hash, valid_remote_peer_id_2)
    remote_handshake_3 = PWP.encode_handshake(@info_hash, valid_remote_peer_id_3)
    remote_handshake_4 = PWP.encode_handshake(@info_hash, valid_remote_peer_id_4)
    remote_handshake_5 = PWP.encode_handshake(@info_hash, valid_remote_peer_id_5)

    destination_pid = MockPeerCoordinator.start_link
    Handshaker.register(@info_hash, destination_pid)

    receiving_pid_1 = ReceivingPeer.start_link(@remote_port, remote_handshake_1)
    receiving_pid_2 = ReceivingPeer.start_link(@remote_port + 1, remote_handshake_2)
    receiving_pid_3 = ReceivingPeer.start_link(@remote_port + 2, remote_handshake_3)
    receiving_pid_4 = ReceivingPeer.start_link(@remote_port + 3, remote_handshake_4)
    receiving_pid_5 = ReceivingPeer.start_link(@remote_port + 4, remote_handshake_5)

    Handshaker.initiate({127,0,0,1}, @remote_port, @info_hash)
    Handshaker.initiate({127,0,0,1}, @remote_port + 1, @info_hash)
    Handshaker.initiate({127,0,0,1}, @remote_port + 2, @info_hash)
    Handshaker.initiate({127,0,0,1}, @remote_port + 3, @info_hash)
    Handshaker.initiate({127,0,0,1}, @remote_port + 4, @info_hash)

    :timer.sleep(200)

    sent_handshake_1 = ReceivingPeer.get_received_handshake(receiving_pid_1)
    sent_handshake_2 = ReceivingPeer.get_received_handshake(receiving_pid_2)
    sent_handshake_3 = ReceivingPeer.get_received_handshake(receiving_pid_3)
    sent_handshake_4 = ReceivingPeer.get_received_handshake(receiving_pid_4)
    sent_handshake_5 = ReceivingPeer.get_received_handshake(receiving_pid_5)
    assert sent_handshake_1 == @local_handshake
    assert sent_handshake_2 == @local_handshake
    assert sent_handshake_3 == @local_handshake
    assert sent_handshake_4 == @local_handshake
    assert sent_handshake_5 == @local_handshake

    {:ok, receiver_results} = MockPeerCoordinator.get_results
    sorted_results = Enum.sort(receiver_results, fn {_, _, id1}, {_, _, id2} ->
      id1 <= id2
    end)
    assert sorted_results == [
      {:initiate_success, {127,0,0,1}, valid_remote_peer_id_1},
      {:initiate_success, {127,0,0,1}, valid_remote_peer_id_2},
      {:initiate_success, {127,0,0,1}, valid_remote_peer_id_3},
      {:initiate_success, {127,0,0,1}, valid_remote_peer_id_4},
      {:initiate_success, {127,0,0,1}, valid_remote_peer_id_5}
    ]
  end


  test "total - 2 initiate success 2 initiate failure 2 receive success 2 receive failure" do
    {:ok, _} = Server.start_link(@local_port)
    {:ok, _} = Handshaker.start_link(@local_peer_id)
    valid_remote_peer_id_1 = "99999999999999999990"
    valid_remote_peer_id_2 = "99999999999999999991"
    valid_remote_peer_id_3 = "99999999999999999992"
    valid_remote_peer_id_4 = "99999999999999999993"
    valid_remote_peer_id_5 = "99999999999999999994"
    valid_remote_peer_id_6 = "99999999999999999995"
    valid_remote_peer_id_7 = "99999999999999999996"
    valid_remote_peer_id_8 = "99999999999999999997"

    remote_handshake_1 = PWP.encode_handshake(@info_hash, valid_remote_peer_id_1)
    remote_handshake_2 = PWP.encode_handshake(@info_hash, valid_remote_peer_id_2)
    remote_handshake_3 = PWP.encode_handshake(@info_hash, valid_remote_peer_id_3) <> "1"
    remote_handshake_4 = PWP.encode_handshake("12345123451234512345", valid_remote_peer_id_4)
    remote_handshake_5 = PWP.encode_handshake(@info_hash, valid_remote_peer_id_5)
    remote_handshake_6 = PWP.encode_handshake(@info_hash, valid_remote_peer_id_6)
    remote_handshake_7 = PWP.encode_handshake(@info_hash, valid_remote_peer_id_7) <> "9"
    remote_handshake_8 = PWP.encode_handshake("54321543215432154321", valid_remote_peer_id_8)

    destination_pid = MockPeerCoordinator.start_link
    Handshaker.register(@info_hash, destination_pid)

    receiving_pid_1 = ReceivingPeer.start_link(@remote_port, remote_handshake_1)
    receiving_pid_2 = ReceivingPeer.start_link(@remote_port + 1, remote_handshake_2)
    receiving_pid_3 = ReceivingPeer.start_link(@remote_port + 2, remote_handshake_3)
    receiving_pid_4 = ReceivingPeer.start_link(@remote_port + 3, remote_handshake_4)
    incoming_pid_1 = IncomingPeer.start_link(@local_port, remote_handshake_5)
    incoming_pid_2 = IncomingPeer.start_link(@local_port, remote_handshake_6)
    incoming_pid_3 = IncomingPeer.start_link(@local_port, remote_handshake_7)
    incoming_pid_4 = IncomingPeer.start_link(@local_port, remote_handshake_8)

    Handshaker.initiate({127,0,0,1}, @remote_port, @info_hash)
    Handshaker.initiate({127,0,0,1}, @remote_port + 1, @info_hash)
    Handshaker.initiate({127,0,0,1}, @remote_port + 2, @info_hash)
    Handshaker.initiate({127,0,0,1}, @remote_port + 3, @info_hash)

    :timer.sleep(200)

    sent_handshake_1 = ReceivingPeer.get_received_handshake(receiving_pid_1)
    sent_handshake_2 = ReceivingPeer.get_received_handshake(receiving_pid_2)
    sent_handshake_3 = ReceivingPeer.get_received_handshake(receiving_pid_3)
    sent_handshake_4 = ReceivingPeer.get_received_handshake(receiving_pid_4)
    sent_handshake_5 = IncomingPeer.get_received_handshake(incoming_pid_1)
    sent_handshake_6 = IncomingPeer.get_received_handshake(incoming_pid_2)
    sent_handshake_7 = IncomingPeer.get_received_handshake(incoming_pid_3)
    sent_handshake_8 = IncomingPeer.get_received_handshake(incoming_pid_4)

    assert sent_handshake_1 == @local_handshake
    assert sent_handshake_2 == @local_handshake
    assert sent_handshake_3 == @local_handshake
    assert sent_handshake_4 == @local_handshake
    assert sent_handshake_5 == @local_handshake
    assert sent_handshake_6 == @local_handshake
    assert sent_handshake_7 == nil
    assert sent_handshake_8 == nil

    {:ok, receiver_results} = MockPeerCoordinator.get_results
    {successful, unsuccessful} = Enum.split_with(receiver_results, fn res ->
      elem(res, 0) == :initiate_success or elem(res, 0) == :receive_success
    end)
    sorted_successful = Enum.sort(successful, fn {_, _, id1}, {_, _, id2} ->
      id1 <= id2
    end)
    assert sorted_successful == [
      {:initiate_success, {127,0,0,1}, valid_remote_peer_id_1},
      {:initiate_success, {127,0,0,1}, valid_remote_peer_id_2},
      {:receive_success, {127,0,0,1}, valid_remote_peer_id_5},
      {:receive_success, {127,0,0,1}, valid_remote_peer_id_6}
    ]
    assert unsuccessful == [
      {:initiate_failure, {127,0,0,1}},
      {:initiate_failure, {127,0,0,1}}
    ]
    Server.stop
  end
end


defmodule Peers.Test.Handshaking.IncomingPeer do
  def start_link(port, handshake_data) do
    {:ok, socket} = :gen_tcp.connect({127,0,0,1}, port, [:binary, active: :false], 1000)
    spawn_link(
      __MODULE__,
      :try_initiate,
      [socket, handshake_data]
    )
  end


  def get_received_handshake(pid) do
    send(pid, {:get, self()})
    receive do
      {^pid, handshake} -> handshake
    after 200 ->
      nil
    end
  end

  def try_initiate(socket, handshake_data) do
    try do
      initiate(socket, handshake_data)
    catch _, _ ->
      nil
    end
  end

  def initiate(socket, handshake_data) do
    :ok = :gen_tcp.send(socket, handshake_data)
    {:ok, handshake_response} = :gen_tcp.recv(socket, 0, 100)
    receive do
      {:get, pid} ->
        send(pid, {self(), handshake_response})
    end
  end
end


defmodule Peers.Test.Handshaking.ReceivingPeer do
  require Logger

  def start_link(port, handshake_data) do
    {:ok, server_socket} = :gen_tcp.listen(port, [:binary, active: :false, reuseaddr: :true])
    spawn_link(
      __MODULE__,
      :try_receive,
      [server_socket, handshake_data]
    )
  end

  def get_received_handshake(pid) do
    send(pid, {:get, self()})
    receive do
      {^pid, handshake} -> handshake
    after 200 ->
      nil
    end
  end


  def try_receive(server_socket, handshake_data) do
    {:ok, socket} = :gen_tcp.accept(server_socket)
    {:ok, data} = :gen_tcp.recv(socket, 0, 100)
    :ok = :gen_tcp.send(socket, handshake_data)
    :timer.sleep(100)
    receive do
      {:get, pid} ->
        send(pid, {self(), data})
    end
  end
end
