defmodule Storage.DirectoryHandler do
  @moduledoc """
  Responsible for all the reads and writes for single metafile download (separate
  directory)


  """
  defstruct path: nil, worker_count: nil

  use GenServer

  require Logger

  alias Core.Registry, as: Registry
  alias Storage.DirectoryHandler, as: DirectoryHandler

  @initial_worker_count 3


  def start_link(info_hash, path) do
    GenServer.start_link(__MODULE__, [info_hash, path])
  end


  def init([info_hash, path]) do
    unless File.exists?(path) do
      Logger.info "Creating directory at path: #{path}"
      File.mkdir_p!(path)
    end
    supervisor_pid = Registry.whereis({:storage, :worker_supervisor, path})
    Enum.each(0..@initial_worker_count, fn id ->
      Storage.WorkerSupervisor.start_worker(supervisor_pid, id)
    end)
    Registry.register({:storage, :directory_handler, info_hash}, self())
    {:ok, %DirectoryHandler{path: path, worker_count: @initial_worker_count}}
  end


  def get_missing(pid) do
    GenServer.call(pid, :get_missing)
  end

  def store(pid, piece, callback) do
    GenServer.cast(pid, {:store, piece, callback})
  end

  def retrieve(pid, index, callback) do
    GenServer.cast(pid, {:retrieve, index, callback})
  end

  def compose(pid, files, callback) do
    GenServer.cast(pid, {:compose, files, callback})
  end


  def handle_call(:get_missing, _from, state = %{path: path}) do
    indexes =
      File.ls!(path)
      |> Enum.filter(&(String.ends_with?(&1, ".piece")))
      |> Enum.map(fn name ->
        [index, _] = String.split(name, ".piece")
        String.to_integer(index)
      end)
      |> Enum.into(MapSet.new())
    {:reply, indexes, state}
  end


  def handle_cast({:store, piece, callback}, state) do
    initiate_store(state, piece, callback)
    {:noreply, state}
  end

  def handle_cast({:retrieve, index, callback}, state) do
    initiate_retrieval(state, index, callback)
    {:noreply, state}
  end

  def handle_cast({:compose, files, callback}, state) do
    initiate_composing(state, files, callback)
    {:noreply, state}
  end


  defp initiate_store(state, %{index: index, data: data}, callback) do
    worker = pick_worker(state, index)
    Storage.Worker.store(worker, index, data, callback)
  end


  defp initiate_retrieval(state, index, callback) do
    worker = pick_worker(state, index)
    Storage.Worker.retrieve(worker, index, callback)
  end


  defp initiate_composing(state, files, callback) do
    worker = pick_worker(state, files)
    Storage.Worker.compose(worker, files, callback)
  end


  defp pick_worker(%{worker_count: count, path: path}, index) do
    # TODO - handle case when worker is down and didnt yet re-register
    worker_id = :erlang.phash2(index, count)
    Registry.whereis({:storage, :worker, {path, worker_id}})
  end
end
