defmodule Announcing.Test.UDPAnnouncer do
  use ExUnit.Case

  alias Announcing.Mock.UDPTracker, as: MockUDPTracker
  alias Announcing.Announcer, as: Announcer


  @info_hash <<1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1>>
  @peer_id <<2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2>>
  @test_peer_data <<1,1,1,1,1,1,2,2,2,2,2,2>>
  @peer_port 11000
  @tracker_port 10000
  @tracker_url "udp://127.0.0.1:#{@tracker_port}"
  @download_info %{
    info_hash: @info_hash,
    peer_id: @peer_id,
    port: @peer_port,
  }

  test "only startup" do
    expected_announce_map = %{
      info_hash: @info_hash,
      peer_id: @peer_id,
      downloaded: 20,
      uploaded: 10,
      left: 30,
      event_id: 2,
      numwant: 20,
      port: @peer_port
    }
    mock_announce_responses = [
      %{
        interval: 100,
        leechers: 10,
        seeders: 5,
        peer_data: @test_peer_data,
      }
    ]
    Process.flag(:trap_exit, :true)

    mock_tracker = MockUDPTracker.start_link(@tracker_port, mock_announce_responses)
    {:ok, announcer} = Announcer.start_link(@tracker_url, @download_info)

    :timer.sleep(1500)

    Process.exit(announcer, :kill)
    requests = MockUDPTracker.get_result(mock_tracker)
    assert length(requests) == 1
    assert requests == [expected_announce_map]
  end

  test "startup, one regular and stopped" do
    expected_announced_maps = [
      %{
        info_hash: @info_hash,
        peer_id: @peer_id,
        downloaded: 20,
        uploaded: 10,
        left: 30,
        event_id: 2,
        numwant: 20,
        port: @peer_port
      },
      %{
        info_hash: @info_hash,
        peer_id: @peer_id,
        downloaded: 20,
        uploaded: 10,
        left: 30,
        event_id: 0,
        numwant: 20,
        port: @peer_port
      },
      %{
        info_hash: @info_hash,
        peer_id: @peer_id,
        downloaded: 20,
        uploaded: 10,
        left: 30,
        event_id: 3,
        numwant: 20,
        port: @peer_port
      }
    ]
    mock_announce_responses = [
      %{
        interval: 1,
        leechers: 10,
        seeders: 5,
        peer_data: @test_peer_data,
      },
      %{
        interval: 1,
        leechers: 10,
        seeders: 5,
        peer_data: @test_peer_data,
      },
      %{
        interval: 1,
        leechers: 10,
        seeders: 5,
        peer_data: @test_peer_data,
      }
    ]
    Process.flag(:trap_exit, :true)

    mock_tracker = MockUDPTracker.start_link(@tracker_port, mock_announce_responses)
    {:ok, announcer} = Announcer.start_link(@tracker_url, @download_info)

    :timer.sleep(1500)
    Process.exit(announcer, :normal)
    :timer.sleep(200)
    requests = MockUDPTracker.get_result(mock_tracker)
    assert length(requests) == 3
    assert requests == expected_announced_maps
  end

  test "startup regular, completed, regular, and stopped" do
    {:ok, registry} = Core.Registry.start_link()
    expected_announced_maps = [
      %{
        info_hash: @info_hash,
        peer_id: @peer_id,
        downloaded: 20,
        uploaded: 10,
        left: 30,
        event_id: 2,
        numwant: 20,
        port: @peer_port
      },
      %{
        info_hash: @info_hash,
        peer_id: @peer_id,
        downloaded: 20,
        uploaded: 10,
        left: 30,
        event_id: 0,
        numwant: 20,
        port: @peer_port
      },
      %{
        info_hash: @info_hash,
        peer_id: @peer_id,
        downloaded: 20,
        uploaded: 10,
        left: 30,
        event_id: 1,
        numwant: 20,
        port: @peer_port
      },
      %{
        info_hash: @info_hash,
        peer_id: @peer_id,
        downloaded: 20,
        uploaded: 10,
        left: 30,
        event_id: 0,
        numwant: 20,
        port: @peer_port
      },
      %{
        info_hash: @info_hash,
        peer_id: @peer_id,
        downloaded: 20,
        uploaded: 10,
        left: 30,
        event_id: 3,
        numwant: 20,
        port: @peer_port
      }
    ]
    mock_announce_responses = [
      %{
        interval: 1,
        leechers: 10,
        seeders: 5,
        peer_data: @test_peer_data,
      },
      %{
        interval: 1,
        leechers: 10,
        seeders: 5,
        peer_data: @test_peer_data,
      },
      %{
        interval: 1,
        leechers: 10,
        seeders: 5,
        peer_data: @test_peer_data,
      },
      %{
        interval: 1,
        leechers: 10,
        seeders: 5,
        peer_data: @test_peer_data,
      },
      %{
        interval: 1,
        leechers: 10,
        seeders: 5,
        peer_data: @test_peer_data,
      }
    ]
    Process.flag(:trap_exit, :true)

    mock_tracker = MockUDPTracker.start_link(@tracker_port, mock_announce_responses)
    {:ok, announcer} = Announcer.start_link(@tracker_url, @download_info)

    :timer.sleep(1200)
    Announcer.announce_completion(@tracker_url)
    :timer.sleep(1200)
    Process.exit(announcer, :normal)
    :timer.sleep(200)
    requests = MockUDPTracker.get_result(mock_tracker)
    assert length(requests) == 5
    assert requests == expected_announced_maps

    Process.exit(registry, :kill)
  end
end


defmodule Announcing.Mock.UDPTracker do
  def start_link(port, responses) do
    case :gen_udp.open(port, [:binary, active: :true]) do
      {:ok, socket} ->
        pid = spawn_link(__MODULE__, :run, [socket, responses, []])
        :gen_udp.controlling_process(socket, pid)
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
      exit(:failed_to_get_results)
    end
  end

  def run(socket, [], requests) do
    :gen_udp.close(socket)
    receive do
      {:stop, sender} ->
        send(sender, {self(), Enum.reverse(requests)})
    end
  end
  def run(socket, [resp | responses], requests) do
    receive do
      {:udp, ^socket, host, port, request} ->
        case respond(socket, resp, host, port, request) do
          {:ok, recorded_request} ->
            run(socket, responses, [recorded_request | requests])

          err = {:error, _reason} ->
            exit(err)
        end

      {:stop, sender} ->
        :gen_udp.close(socket)
        send(sender, {self(), Enum.reverse(requests)})
    end
  end


  defp respond(socket, response, host, port, request) do
    with {:ok, transaction_id} <- parse_connect_request(request),
         send_connect_response(socket, host, port, transaction_id),
         {:ok, transaction_id_2, request_map} <- receive_announce_request(socket, host, port),
         :ok = send_announce_response(socket, host, port, transaction_id_2, response) do
      {:ok, request_map}
    end
  end


  defp parse_connect_request(<<
    0x41727101980 :: big-integer-size(64),
    0 :: big-integer-size(32),
    transaction_id :: big-integer-size(32)
  >>) do
    {:ok, transaction_id}
  end
  defp parse_connect_request(bin) when byte_size(bin) == 20, do: {:error, :bad_content}
  defp parse_connect_request(_), do: {:error, :bad_length}


  defp send_connect_response(socket, host, port, transaction_id) do
    bin = <<0 :: big-integer-size(32),
            transaction_id :: big-integer-size(32),
            12345 :: big-integer-size(64)>>
    :ok = :gen_udp.send(socket, host, port, bin)
  end


  defp receive_announce_request(socket, host, port) do
    receive do
      {:udp, ^socket, ^host, ^port, data} ->
        parse_announce_request(data)

    after 1000 ->
      {:error, :announce_request_too_slow}
    end
  end


  defp parse_announce_request(<<
    12345 :: big-integer-size(64),
    1 :: big-integer-size(32),
    transaction_id :: big-integer-size(32),
    info_hash :: bytes-size(20),
    peer_id :: bytes-size(20),
    downloaded :: big-integer-size(64),
    left :: big-integer-size(64),
    uploaded :: big-integer-size(64),
    event_id :: big-integer-size(32),
    0 :: big-integer-size(32),
    _ :: big-integer-size(32),
    numwant :: big-integer-size(32),
    port :: big-integer-size(16)
  >>) do
    request_map = %{
      info_hash: info_hash,
      peer_id: peer_id,
      downloaded: downloaded,
      uploaded: uploaded,
      left: left,
      event_id: event_id,
      numwant: numwant,
      port: port
    }
    {:ok, transaction_id, request_map}
  end
  defp parse_announce_request(_), do: {:error, :bad_match}


  defp send_announce_response(socket, host, port, transaction_id, response) do
    bin = <<1 :: big-integer-size(32),
            transaction_id :: big-integer-size(32),
            response.interval :: big-integer-size(32),
            response.leechers :: big-integer-size(32),
            response.seeders :: big-integer-size(32),
            response.peer_data :: binary>>
    :gen_udp.send(socket, host, port, bin)
  end
end
