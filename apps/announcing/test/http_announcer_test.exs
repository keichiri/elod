defmodule Announcing.Test.HTTPAnnouncer do
  use ExUnit.Case

  alias Announcing.Announcer, as: Announcer
  alias Announcing.Mock.HTTPTracker, as: MockHTTPTracker


  @info_hash <<1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1>>
  @peer_id <<2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2>>
  @test_peer_data <<1,1,1,1,1,1,2,2,2,2,2,2>>
  @peer_port 11000
  @tracker_port 20000
  @tracker_url "http://127.0.0.1:#{@tracker_port}"
  @download_info %{
    info_hash: @info_hash,
    peer_id: @peer_id,
    port: @peer_port,
  }

  test "only startup" do
    :inets.start()
    expected_announce_map = %{
      info_hash: @info_hash,
      peer_id: @peer_id,
      downloaded: 20,
      uploaded: 10,
      left: 30,
      event: "started",
      numwant: 20,
      port: @peer_port,
      compact: 1,
    }
    mock_announce_responses = [
      %{
        interval: 100,
        incomplete: 10,
        complete: 5,
        peers: @test_peer_data,
      }
    ]
    Process.flag(:trap_exit, :true)

    mock_tracker = MockHTTPTracker.start_link(@tracker_port, mock_announce_responses)
    {:ok, announcer} = Announcer.start_link(@tracker_url, @download_info)
    :timer.sleep(1500)
    Process.exit(announcer, :kill)
    requests = MockHTTPTracker.get_result(mock_tracker)

    assert length(requests) == 1
    assert requests == [expected_announce_map]
  end


  test "startup and stop" do
    :inets.start()
    expected_announced_maps = [
      %{
        info_hash: @info_hash,
        peer_id: @peer_id,
        downloaded: 20,
        uploaded: 10,
        left: 30,
        event: "started",
        numwant: 20,
        port: @peer_port,
        compact: 1,
      },
      %{
        info_hash: @info_hash,
        peer_id: @peer_id,
        downloaded: 20,
        uploaded: 10,
        left: 30,
        event: "stopped",
        numwant: 20,
        port: @peer_port,
        compact: 1,
      },
    ]
    mock_announce_responses = [
      %{
        interval: 100,
        incomplete: 10,
        complete: 5,
        peers: @test_peer_data,
      },
      %{
        interval: 100,
        incomplete: 10,
        complete: 5,
        peers: @test_peer_data,
      }
    ]
    Process.flag(:trap_exit, :true)

    mock_tracker = MockHTTPTracker.start_link(@tracker_port, mock_announce_responses)
    {:ok, announcer} = Announcer.start_link(@tracker_url, @download_info)
    :timer.sleep(100)
    Process.exit(announcer, :ok)
    :timer.sleep(100)
    requests = MockHTTPTracker.get_result(mock_tracker)

    assert length(requests) == 2
    assert requests == expected_announced_maps
  end

  test "startup regular and stop" do
    :inets.start()
    expected_announced_maps = [
      %{
        info_hash: @info_hash,
        peer_id: @peer_id,
        downloaded: 20,
        uploaded: 10,
        left: 30,
        event: "started",
        numwant: 20,
        port: @peer_port,
        compact: 1,
      },
      %{
        info_hash: @info_hash,
        peer_id: @peer_id,
        downloaded: 20,
        uploaded: 10,
        left: 30,
        event: "",
        numwant: 20,
        port: @peer_port,
        compact: 1,
        trackerid: "tracker-id"
      },
      %{
        info_hash: @info_hash,
        peer_id: @peer_id,
        downloaded: 20,
        uploaded: 10,
        left: 30,
        event: "stopped",
        numwant: 20,
        port: @peer_port,
        compact: 1,
        trackerid: "tracker-id2"
      },
    ]
    mock_announce_responses = [
      %{
        :interval => 1,
        :incomplete => 10,
        :complete => 5,
        :peers => @test_peer_data,
        "tracker id" => "tracker-id"
      },
      %{
        :interval => 1,
        :incomplete => 10,
        :complete => 5,
        :peers => @test_peer_data,
        "tracker id" => "tracker-id2"
      },
      %{
        :interval => 1,
        :incomplete => 10,
        :complete => 5,
        :peers => @test_peer_data,
      },
    ]
    Process.flag(:trap_exit, :true)

    mock_tracker = MockHTTPTracker.start_link(@tracker_port, mock_announce_responses)
    {:ok, announcer} = Announcer.start_link(@tracker_url, @download_info)
    :timer.sleep(1100)
    Process.exit(announcer, :ok)
    :timer.sleep(100)
    requests = MockHTTPTracker.get_result(mock_tracker)

    assert length(requests) == 3
    assert requests == expected_announced_maps
  end

  test "startup regular completed regular and stop" do
    {:ok, registry} = Core.Registry.start_link()
    :inets.start()
    expected_announced_maps = [
      %{
        info_hash: @info_hash,
        peer_id: @peer_id,
        downloaded: 20,
        uploaded: 10,
        left: 30,
        event: "started",
        numwant: 20,
        port: @peer_port,
        compact: 1,
      },
      %{
        info_hash: @info_hash,
        peer_id: @peer_id,
        downloaded: 20,
        uploaded: 10,
        left: 30,
        event: "",
        numwant: 20,
        port: @peer_port,
        compact: 1,
        trackerid: "tracker-id"
      },
      %{
        info_hash: @info_hash,
        peer_id: @peer_id,
        downloaded: 20,
        uploaded: 10,
        left: 30,
        event: "completed",
        numwant: 20,
        port: @peer_port,
        compact: 1,
        trackerid: "tracker-id"
      },
      %{
        info_hash: @info_hash,
        peer_id: @peer_id,
        downloaded: 20,
        uploaded: 10,
        left: 30,
        event: "",
        numwant: 20,
        port: @peer_port,
        compact: 1,
        trackerid: "tracker-id"
      },
      %{
        info_hash: @info_hash,
        peer_id: @peer_id,
        downloaded: 20,
        uploaded: 10,
        left: 30,
        event: "stopped",
        numwant: 20,
        port: @peer_port,
        compact: 1,
        trackerid: "tracker-id2"
      },
    ]
    mock_announce_responses = [
      %{
        :interval => 1,
        :incomplete => 10,
        :complete => 5,
        :peers => @test_peer_data,
        "tracker id" => "tracker-id"
      },
      %{
        :interval => 1,
        :incomplete => 10,
        :complete => 5,
        :peers => @test_peer_data,
        "tracker id" => "tracker-id"
      },
      %{
        :interval => 1,
        :incomplete => 10,
        :complete => 5,
        :peers => @test_peer_data,
        "tracker id" => "tracker-id"
      },
      %{
        :interval => 1,
        :incomplete => 10,
        :complete => 5,
        :peers => @test_peer_data,
        "tracker id" => "tracker-id2"
      },
      %{
        :interval => 1,
        :incomplete => 10,
        :complete => 5,
        :peers => @test_peer_data,
      },
    ]
    Process.flag(:trap_exit, :true)

    mock_tracker = MockHTTPTracker.start_link(@tracker_port, mock_announce_responses)
    {:ok, announcer} = Announcer.start_link(@tracker_url, @download_info)
    :timer.sleep(1100)
    Announcer.announce_completion(@tracker_url)
    :timer.sleep(1100)
    Process.exit(announcer, :ok)
    :timer.sleep(100)
    requests = MockHTTPTracker.get_result(mock_tracker)

    assert length(requests) == 5
    assert requests == expected_announced_maps
    Process.exit(registry, :normal)
  end
end


defmodule Announcing.Mock.HTTPTracker do
  def start_link(port, responses) do
    case :gen_tcp.listen(port, [:binary, active: :false, reuseaddr: :true]) do
      {:ok, server_socket} ->
        pid = spawn_link(__MODULE__, :run, [server_socket, responses, []])
        :gen_tcp.controlling_process(server_socket, pid)
        pid

      err ->
        err
    end
  end

  def get_result(pid) do
    send(pid, {:stop, self()})
    receive do
      {^pid, requests} ->
        requests

    after 100 ->
      alive = Process.alive?(pid)
      exit({:failed_to_get_requests, alive})
    end
  end


  def run(socket, [], requests) do
    receive do
      {:stop, sender} ->
        send(sender, {self(), Enum.reverse(requests)})
        :gen_tcp.close(socket)
    end
  end
  def run(server_socket, [resp | responses], requests) do
    receive do
      {:stop, sender}->
        send(sender, {self(), :premature_stop})
    after 0 ->
      nil
    end

    case :gen_tcp.accept(server_socket) do
      {:ok, socket} ->
        request = process_request(socket, resp)
        :gen_tcp.close(socket)
        run(server_socket, responses, [request | requests])
      {:error, reason} ->
        :gen_tcp.close(server_socket)
        exit({:error, reason})
    end
  end


  def process_request(socket, resp) do
    case :gen_tcp.recv(socket, 0) do
      {:ok, request_data} ->
        request = parse_http_request(request_data)
        encoded_response = encode(resp)
        :ok = :gen_tcp.send(socket, encoded_response)
        request
    end
  end


  defp parse_http_request(data) do
    String.split(data, "\r\n")
    |> List.first
    |> String.split(" ")
    |> Enum.at(1)
    |> String.split("?")
    |> List.last
    |> URI.decode_query
    |> Enum.reduce(%{}, fn {k, v}, acc ->
      v = try do
        String.to_integer(v)
      catch
        _, _ ->
          v
      end
      Map.put(acc, String.to_atom(k), v)
    end)
  end


  defp encode(resp) do
    resp = Enum.reduce(resp, %{}, fn {k, v}, acc ->
      Map.put(acc, to_string(k), v)
    end)
    {:ok, bencoded_resp} = Core.Bencoding.encode(resp)
    "HTTP/1.1 200 OK\r\ncontent-length: #{byte_size(bencoded_resp)}\r\n\r\n#{bencoded_resp}"
  end
end
