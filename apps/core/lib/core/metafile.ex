defmodule Core.Metafile do
  @moduledoc """
  Representation of a BitTorrent metafile (.torrent file).

  Currently includes only necessary, core fieds.

  Key components of metafile:
    1. info hash - sha1 hash of the bencoded info section
    2. announce url - URL of the main tracker for given metafile
    3. files - files that are to be downloaded
    4. pieces - pieces that compose given files
  """

  defstruct info_hash: nil, announce_url: nil, files: nil, pieces: nil

  alias Core.Metafile, as: Metafile
  alias Core.Bencoding, as: Bencoding
  alias Core.File, as: File
  alias Core.Piece, as: Piece


  @doc """
  Attemps to create a metafile representation from binary input.

  Input is expected to be bencoded.

  ## Returns:
    {:ok, metafile}
    {:error, reason}
  """
  def parse_from_binary(binary) do
    case Bencoding.decode(binary) do
      {:ok, %{"announce" => announce_url, "info" => info}} ->
        with {:ok, files} <- File.create_from_info(info),
             {:ok, pieces} <- Piece.create_from_info(info) do
          info_hash = calculate_info_hash(binary, info)
          fixed_pieces = fix_pieces_length(files, pieces)
          metafile = %Metafile{
            info_hash: info_hash,
            announce_url: announce_url,
            files: files,
            pieces: fixed_pieces
          }
          {:ok, metafile}
        end

      {:ok, item} when is_map(item) ->
        {:error, :missing_required_fields}

      {:ok, _item} ->
        {:error, :decoded_content_not_map}

      err ->
        err
    end
  end


  defp fix_pieces_length(files, pieces) do
    total_files_length = Enum.reduce(files, 0, fn %{length: length}, acc_length ->
      length + acc_length
    end)
    last_piece = Enum.at(pieces, -1)
    fixed_length = rem(total_files_length, last_piece.length)
    fixed_last_piece = %{last_piece | length: fixed_length}
    List.replace_at(pieces, -1, fixed_last_piece)
  end


  @doc """
  Calculates the hash of bencoded info dictionary.
  Needs to use original one (from the file content), since the process of
  encoding => decoding might not preserve the original ordering when serialized
  """
  defp calculate_info_hash(encoded_metafile, info) do
    {:ok, encoded_info} = Bencoding.encode(info)
    info_length = byte_size(encoded_info)
    [pre, post] = String.split(encoded_metafile, "4:info")
    start_index = byte_size(pre)
    real_encoded_info = String.slice(post, 0, info_length)
    :crypto.hash(:sha, real_encoded_info)
  end
end
