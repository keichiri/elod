defmodule Peers.Test.Channel do
  use ExUnit.Case

  alias Peers.Channel, as: Channel
  alias Peers.PWP, as: PWP
  alias Peers.Test.Channel.MockRemotePeer, as: MockRemotePeer


  @server_port 41000


  def open_sockets(port) do
    pid = self()
    spawn(fn ->
      case :gen_tcp.listen(port, [:binary, active: :false, reuseaddr: :true]) do
        {:ok, server_socket} ->
          case :gen_tcp.accept(server_socket, 1000) do
            {:ok, socket} ->
              :gen_tcp.controlling_process(socket, pid)
              send(pid, socket)

            err ->
              send(pid, err)
          end
        err ->
          send(pid, err)
      end
    end)
    :timer.sleep(20)
    spawn(fn ->
      case :gen_tcp.connect({127,0,0,1}, port, [:binary, active: :false], 200) do
        {:ok, socket} ->
          :gen_tcp.controlling_process(socket, pid)
          send(pid, socket)

        err ->
          send(pid, err)
      end
    end)

    receive do
      {:error, reason} ->
        {:error, reason}

      socket1 ->
        receive do
          socket2 ->
            {:ok, {socket1, socket2}}
        end
    end
  end


  def get_messages() do
    get_messages([])
  end
  def get_messages(messages) do
    receive do
      {:msg, msg} ->
        get_messages([msg | messages])
    after 100 ->
      Enum.reverse(messages)
    end
  end


  test "exchanging single message" do
    {:ok, {socket1, socket2}} = open_sockets(@server_port)
    incoming_message_encoded = PWP.encode({:have, 5})
    outgoing_message = {:request, 10, 20, 30}

    remote_peer_pid = MockRemotePeer.start_link(socket1, [incoming_message_encoded])
    pid = self()
    on_incoming_message = fn msg ->
      send(pid, {:msg, msg})
    end
    {:ok, channel_pid} = Channel.start_link(socket2, {127,0,0,1}, on_incoming_message)
    Channel.send_message(channel_pid, outgoing_message)
    :timer.sleep(100)

    sent_to_remote_peer = MockRemotePeer.get_received_messages(remote_peer_pid)
    assert sent_to_remote_peer == PWP.encode(outgoing_message)
    assert_receive({:msg, {:have, 5}})

    :gen_tcp.close(socket1)
    :gen_tcp.close(socket2)
  end


  test "receiving single invalid message" do
    {:ok, {socket1, socket2}} = open_sockets(@server_port)
    incoming_message_encoded = PWP.encode({:have, 5})

    remote_peer_pid = MockRemotePeer.start_link(socket1, ["invalid_message"])
    pid = self()
    on_incoming_message = fn msg ->
      send(pid, {:msg, msg})
    end
    {:ok, channel_pid} = Channel.start_link(socket2, {127,0,0,1}, on_incoming_message)
    Process.flag(:trap_exit, true)
    :timer.sleep(500)
    assert_receive({:'EXIT', channel_pid, {:error, :invalid_message}})

    :gen_tcp.close(socket1)
    :gen_tcp.close(socket2)
  end

  test "exchanging multiple messages" do
    {:ok, {socket1, socket2}} = open_sockets(@server_port)
    incoming_messages = [
      {:have, 5},
      :unchoke,
      {:bitfield, "test_bitfield"},
      {:cancel, 10, 20, 30},
      {:request, 100, 200, 300}
    ]
    outgoing_messages = [
      :choke,
      {:have, 20},
      {:cancel, 0, 0, 200},
      {:piece, 10, 10, "test_piece"},
      :interested,
      {:request, 10, 20, 30},
      :choke,
      :keep_alive,
      :unchoke
    ]
    incoming_messages_encoded = Enum.map(incoming_messages, &PWP.encode/1)
    outgoing_messages_encoded = Enum.map(outgoing_messages, &PWP.encode/1)
    outgoing_content = Enum.join(outgoing_messages_encoded, "")

    remote_peer_pid = MockRemotePeer.start_link(socket1, incoming_messages_encoded)
    pid = self()
    on_incoming_message = fn msg ->
      send(pid, {:msg, msg})
    end
    {:ok, channel_pid} = Channel.start_link(socket2, {127,0,0,1}, on_incoming_message)
    Enum.each(outgoing_messages, fn msg ->
      Channel.send_message(channel_pid, msg)
    end)
    :timer.sleep(500)

    sent_to_remote_peer = MockRemotePeer.get_received_messages(remote_peer_pid)
    received_messages = get_messages()
    assert received_messages == incoming_messages
    assert sent_to_remote_peer == outgoing_content

    :gen_tcp.close(socket1)
    :gen_tcp.close(socket2)
  end
end


defmodule Peers.Test.Channel.MockRemotePeer do
  def start_link(socket, encoded_messages) do
    spawn_link(__MODULE__, :exchange, [socket, encoded_messages, ""])
  end

  def get_received_messages(pid) do
    send(pid, {:get, self()})
    receive do
      {^pid, messages} ->
        messages
    after 200 ->
      nil
    end
  end


  def exchange(socket, [], received) do
    case :gen_tcp.recv(socket, 0, 50) do
      {:ok, content} ->
        exchange(socket, [], received <> content)

      _ ->
        receive do
          {:get, sender} ->
            send(sender, {self(), received})
        end
    end
  end
  def exchange(socket, [encoded_message | encoded_messages], received) do
    :ok = :gen_tcp.send(socket, encoded_message)
    case :gen_tcp.recv(socket, 0, 50) do
      {:ok, content} ->
        exchange(socket, encoded_messages, received <> content)

      {:error, :timeout} ->
        exchange(socket, encoded_messages, received)
    end
  end
end
