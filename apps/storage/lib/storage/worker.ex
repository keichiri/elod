defmodule Storage.Worker do
  @moduledoc """
  Performs the file system operations on a single directory.
  A DirectoryHandler coordinates one or more workers.

  """

  defstruct path: nil, id: nil

  use GenServer

  require Logger


  def start_link(path, id) do
    GenServer.start_link(__MODULE__, [path, id])
  end

  @doc """
  Orders a worker to store piece.

  ## Parameters:
    - pid: pid of the worker process
    - index: index of piece to be stored
    - data: data of piece to be stored
    - fun: function to be executed with piece's index once piece is stored
  """
  def store(pid, index, data, fun) do
    GenServer.cast(pid, {:store, index, data, fun})
  end


  @doc """
  Orders a worker to retrieve piece.

  ## Parameters:
    - pid: pid of the worker process
    - index: index of piece to be retrieved
    - fun: function to be executed with piece's index and data once it is retrieved
  """
  def retrieve(pid, index, fun) do
    GenServer.cast(pid, {:retrieve, index, fun})
  end


  @doc """
  Orders a worker to compose pieces.

  ## Parameters:
    - pid: pid of the worker process
    - files: list of Core.File structs representing files to be composed
    - fun: function to be executed once pieces are composed
  """
  def compose(pid, files, fun) do
    GenServer.cast(pid, {:compose_pieces, files, fun})
  end


  def init([path, id]) do
    Core.Registry.register({:storage, :worker, {path, id}}, self())
    Process.flag(:trap_exit, true)
    {:ok, %Storage.Worker{path: path, id: id}}
  end


  def handle_cast({:store, index, data, fun}, state = %{path: path}) do
    store_piece(path, index, data, fun)
    {:noreply, state}
  end

  def handle_cast({:retrieve, index, fun}, state = %{path: path}) do
    retrieve_piece(path, index, fun)
    {:noreply, state}
  end

  def handle_cast({:compose_pieces, files, fun}, state = %{path: path}) do
    compose_pieces(path, files, fun)
    {:noreply, state}
  end

  def terminate(reason, state) do
    unless reason == :normal do
      Logger.warn "Worker terminating because of #{inspect reason}"
    end
    Core.Registry.deregister({:storage, :worker, {state.path, state.id}})
    :ok
  end


  defp store_piece(path, index, data, fun) do
    full_path = piece_path(path, index)
    :ok = File.write!(full_path, data)
    Logger.debug "Stored piece. Path: #{full_path}"
    fun.(index)
  end


  defp retrieve_piece(path, index, fun) do
    full_path = piece_path(path, index)
    content = File.read!(full_path)
    Logger.debug "Retrieved piece. Path: #{full_path}"
    fun.(index, content)
  end


  defp compose_pieces(path, files, fun) do
    paths = sorted_piece_paths(path)
    index = 0

    Enum.reduce(files, {paths, index}, fn file = %{length: length}, {available_paths, starting_index} ->
      Logger.debug "Populating file at path: #{file.path}"
      file_handle = open_file(path, file)
      populate_file(file_handle, length, available_paths, starting_index)
    end)
    fun.(path)
  end


  defp piece_path(base, index) do
    Path.join(base, "#{index}.piece")
  end


  defp sorted_piece_paths(path) do
    File.ls!(path)
    |> Enum.filter(&(String.ends_with?(&1, ".piece")))
    |> Enum.sort(fn first, second ->
      first_index = String.to_integer(hd(String.split(first, ".piece")))
      second_index = String.to_integer(hd(String.split(second, ".piece")))
      first_index <= second_index
    end)
    |> Enum.map(&(Path.join(path, &1)))
  end


  defp open_file(base, %{path: file_path}) do
    dir_subpath = Path.dirname(file_path)
    dir_path = Path.join(base, dir_subpath)
    unless File.exists?(dir_path) do
      Logger.debug "Creating path: #{dir_path}"
      :ok = File.mkdir_p!(dir_path)
    end
    file_path = Path.join(base, file_path)
    File.open!(file_path, [:write])
  end


  defp populate_file(file_handle, 0, paths, index) do
    :ok = File.close(file_handle)
    {paths, index}
  end
  defp populate_file(file_handle, left, [piece_path | remaining_paths] = paths, starting_index) do
    piece_content = File.read!(piece_path)
    {_written_content, piece_content} = String.split_at(piece_content, starting_index)
    {to_write, remaining} = String.split_at(piece_content, left)
    :ok = IO.write(file_handle, to_write)
    written = byte_size(to_write)

    if byte_size(remaining) == 0 do
      populate_file(file_handle, left - written, remaining_paths, 0)
    else
      populate_file(file_handle, left - written, paths, starting_index + written)
    end
  end
end
