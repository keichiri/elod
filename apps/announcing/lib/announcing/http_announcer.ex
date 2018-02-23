defmodule Announcing.HTTPAnnouncer do
  @moduledoc """
  Performs announcing to tracker using HTTP.

  All of the announce parameters are sent as URL-encoded values in GET request.

  Tracker response contains bencoded dictionary.

  NOTE - Version 0.1 handles errors by simply logging and exiting.
  """

  defstruct url: nil,
            dl_info: nil,
            next_announce: nil,
            tracker_id: nil

  alias Announcing.Announcer, as: Announcer
  alias Announcing.HTTPAnnouncer, as: HTTPAnnouncer

  use GenServer

  require Logger


  def start_link(url, download_info) do
    GenServer.start_link(__MODULE__, {url, download_info})
  end


  def init({url, dl_info}) do
    Logger.info "Starting HTTP announcer for URL: #{url}"
    Process.flag(:trap_exit, :true)
    Announcer.register(url)
    state = %HTTPAnnouncer{
      url: url,
      dl_info: dl_info,
    }
    {:ok, state, 0}
  end


  # NOTE - not processing tracker's response. Should it?
  def handle_cast(:announce_completion, state) do
    attempt_announce(state, "completed")
  end


  def handle_info(:timeout, state = %{next_announce: next_announce}) do
    event = if next_announce do "" else "started" end
    attempt_announce(state, event)
  end


  def terminate(reason, state = %{url: url, next_announce: next_announce}) do
    unless reason == :normal do
      Logger.error "Announcer for URL: #{url} terminating because of: #{inspect reason}"
    end
    if next_announce do
      announce(state, "stopped")
    end
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


  defp announce(state = %{url: base_url}, event) do
    Logger.debug "Starting announce for event: #{event} to #{state.url}"
    announce_params = prepare_announce_params(state, event)
    full_url = create_url(base_url, announce_params)

    with {:ok, response_content} <- call_tracker(full_url),
         {:ok, decoded_resp} <- Core.Bencoding.decode(response_content) do
      parse_tracker_response(decoded_resp)
    end
  end


  defp prepare_announce_params(%{
    dl_info: dl_info,
    tracker_id: tracker_id,
  }, event) do
    params =
      Stats.get(dl_info.info_hash)
      |> Map.merge(dl_info)
      |> Map.put(:event, event)
      |> Map.put(:numwant, 20) # TODO
      |> Map.put(:compact, 1)

    if tracker_id do
      Map.put(params, :trackerid, tracker_id)
    else
      params
    end
  end


  defp create_url(base_url, params) do
    base_url <> "?" <> URI.encode_query(params)
  end

  # NOTE - not specifying timeout here
  defp call_tracker(full_url) do
    full_url
    |> String.to_charlist
    |> :httpc.request
    |> extract_response_content
  end

  defp extract_response_content({:ok, {{_, 200, _}, _, response_body}}) do
    {:ok, List.to_string(response_body)}
  end
  defp extract_response_content({:ok, _}), do: {:error, :bad_http_status}
  defp extract_response_content({:error, reason}), do: {:error, reason}


  defp parse_tracker_response(%{"failure reason" => failure_reason}) do
    {:error, failure_reason}
  end
  defp parse_tracker_response(resp = %{
    "interval" => interval,
    "complete" => complete,
    "incomplete" => incomplete,
    "peers" => peers,
  }) do
    tracker_id = Map.get(resp, "tracker id")
    warning = Map.get(resp, "warning message")
    if warning do
      Logger.error "Tracker returned warning: #{warning}"
    end
    {:ok, {interval, {complete, incomplete, peers}, tracker_id}}
  end
  defp parse_tracker_response(resp) do
    IO.puts "Response: #{inspect resp}"
    {:error, :invalid_tracker_response}
  end


  defp process_tracker_response(state, {interval, peer_data, tracker_id}) do
    Logger.debug "Tracker for URL: #{state.url} gave interval: #{interval} and peer data: #{inspect peer_data}"
    Announcer.report_peer_data(state.dl_info, peer_data)
    next_announce = :os.system_time(:seconds) + interval
    new_state = %{state | next_announce: next_announce}
    if tracker_id do
      %{new_state | tracker_id: tracker_id}
    else
      new_state
    end
  end

end
