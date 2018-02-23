defmodule Announcing.Announcer do
  @moduledoc """
  Contains announcer-related API.
  Hides away the two underlying protocols (UDP and HTTP).

  Each Announcer is expected to register himself on startup with key being
  {:announcer, announce_url}
  NOTE - this should be responsibility of the supervisor I feel, but I didn't
  find a good way to override supervisor's start/restart behavior

  NOTE - should we have tracker adapter modules? Which would maybe provide call function
  """

  alias Announcing.HTTPAnnouncer, as: HTTPAnnouncer
  alias Announcing.UDPAnnouncer, as: UDPAnnouncer
  alias Core.Registry, as: Registry


  @doc """
  Attempts to start announcer for provided announce URL (tracker URL)

  ## Parameters:
    - announce_url: Tracker's URL. Should have either HTTP or UDP scheme.
    - download_info: Map containing general info for given download process.

  ## Returns:
    {:ok, pid}
    {:error, reason}
  """
  def start_link(announce_url, download_info) do
    case URI.parse(announce_url) do
      %URI{scheme: "udp"} ->
        UDPAnnouncer.start_link(announce_url, download_info)

      %URI{scheme: s} when s == "http" or s == "https" ->
        HTTPAnnouncer.start_link(announce_url, download_info)

      %URI{scheme: nil} ->
        {:error, :invalid_url}

      %URI{scheme: _} ->
        {:error, :unsupported_protocol}
    end
  end

  @doc """
  Called by DownloadCoordinator when a download is completed.
  NOTE - should the parameter be url or info hash?
  """
  def announce_completion(url) do
    pid = Registry.whereis({:announcer, url})
    GenServer.cast(pid, :announce_completion)
  end


  def register(url) do
    Registry.register({:announcer, url}, self())
  end


  def deregister(url) do
    Registry.deregister({:announcer, url})
  end


  def report_peer_data(dl_info, peer_data) do
    # TODO - implement in Peers
    nil
  end




  def calculate_sleep_time(next_announce) do
    now = :os.system_time(:seconds)
    if next_announce > now do
      (next_announce - now) * 1000
    else
      0
    end
  end
end
