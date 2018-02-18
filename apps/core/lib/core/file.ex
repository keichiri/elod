defmodule Core.File do
  @moduledoc """
  Represents a file as described in metafile (.torrent file)

  A single download process contains one or more files, which are described
  with specified fields in metafile
  """

  defstruct path: nil, length: nil

  alias Core.File, as: File


  @doc """
  Creates file representations from metafile (.torrent file).

  Metafile can describe either a single file (name and length fields) or
  multiple files (name and files fields)

  ## Returns:
   {:ok, files} - where files is a list of Core.File structs
   {:error, reason}
  """
  def create_from_info(%{"name" => name, "length" => length}) do
    files = [%File{path: name, length: length}]
    {:ok, files}
  end
  def create_from_info(%{"name" => base, "files" => file_maps}) do
    files = Enum.map(file_maps, fn %{"length" => length, "path" => path_items} ->
      full_path = Path.join([base | path_items])
      %File{path: full_path, length: length}
    end)
    {:ok, files}
  end
  def from_info(info) when is_map(info), do: {:error, :missing_required_fields}
  def from_info(_info), do: {:error, :invalid_info}
end
