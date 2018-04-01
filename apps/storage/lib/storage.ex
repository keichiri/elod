defmodule Storage do
  alias Core.Registry, as: Registry


  def activate_directory(info_hash, dir_name) do
    Storage.Overseer.activate_directory(info_hash, dir_name)
  end

  def deactivate_directory(info_hash) do
    Storage.Overseer.deactivate_directory(info_hash)
  end


  @doc """
  Synchronous call done at every download (re)start, in order to check the initial
  state and prepare the local bitfield.

  ## Returns:
    mapset of existing indexes
  """
  def get_missing(info_hash) do
    pid = Registry.whereis({:storage, :directory_handler, info_hash})
    Storage.DirectoryHandler.get_missing(pid)
  end


  def store(info_hash, piece, callback) do
     pid = Registry.whereis({:storage, :directory_handler, info_hash})
     Storage.DirectoryHandler.store(pid, piece, callback)
  end


  def retrieve(info_hash, index, callback) do
    pid = Registry.whereis({:storage, :directory_handler, info_hash})
    Storage.DirectoryHandler.retrieve(pid, index, callback)
  end


  def compose(info_hash, files, callback) do
    pid = Registry.whereis({:storage, :directory_handler, info_hash})
    Storage.DirectoryHandler.compose(pid, files, callback)
  end
end
