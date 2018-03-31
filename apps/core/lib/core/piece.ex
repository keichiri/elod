defmodule Core.Block do
  defstruct index: nil, offset: nil, length: nil, data: nil
end


defmodule Core.Piece do
  @moduledoc """
  Represents a piece as described in metafile (.torrent file)

  Pieces are one of the main components of the BitTorrent Protocol.
  """

  defstruct index: nil, hash: nil, length: nil, data: nil

  alias Core.Piece, as: Piece
  alias Core.Block, as: Block

  # TODO - check the correct default size, and make it configurable
  @block_size 512


  @doc """
  Creates piece representations from metafile (.torrent file)

  Metafile contains two fields related to pieces:
    1. length - length of each piece except the last one (which has to be calculated)
    2. pieces - string representing concatenations of each piece's sha1 hash

  ## Returns:
    {:ok, pieces} - where pieces is a list of Core.Piece structs
    {:error, reason}
  """
  def create_from_info(%{"piece length" => length, "pieces" => pieces_hash})
    when rem(byte_size(pieces_hash), 20) == 0 do
    pieces =
      (for <<hash :: bytes-size(20) <- pieces_hash>>, do: hash)
      |> Stream.with_index
      |> Enum.map(fn {hash, index} ->
        %Piece{index: index, hash: hash, length: length}
      end)
    {:ok, pieces}
  end
  def create_from_info(%{"piece length" => _length, "pieces" => _pieces_hash}) do
    {:error, :invalid_pieces_hash}
  end
  def create_from_info(input) when is_map(input), do: {:error, :missing_required_fields}
  def create_from_info(_input), do: {:error, :invalid_info}


  def split(%{index: index, length: length}) do
    split(0, length, index, [])
  end

  defp split(offset, length, _index, blocks) when offset >= length do
    Enum.reverse(blocks)
  end
  defp split(offset, length, index, blocks) do
    block_length = if offset + @block_size <= length do
      @block_size
    else
      length - offset
    end
    block = %Block{index: index, offset: offset, length: block_length}
    split(offset + @block_size, length, index, [block | blocks])
  end
end
