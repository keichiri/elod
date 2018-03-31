defmodule Core.Bitfield do
  require Bitwise


  def create(pieces, existing_indexes) do
    pieces
    |> Enum.map(fn %{index: index} -> index  end)
    |> Enum.chunk(8, 8, [])
    |> Enum.map(fn indexes ->
      indexes
      |> Enum.with_index
      |> Enum.reduce(0, fn {piece_index, index}, acc ->
        if MapSet.member?(existing_indexes, piece_index) do
          acc + Bitwise.<<<(1, 7-index)
        else
          acc
        end
      end)
    end)
    |> Enum.into(<<>>, &(<<&1>>))
  end


  def get_existing_indexes(bitfield) do
    bitfield
    |> String.codepoints
    |> Stream.map(fn <<x>> -> x end)
    |> Stream.with_index
    |> Enum.map(fn {byte_value, index} ->
      0..7
      |> Enum.filter(fn pos ->
        Bitwise.band(byte_value, Bitwise.<<<(1, 7 - pos)) > 0
      end)
      |> Enum.map(fn pos ->
        index * 8 + pos
      end)
    end)
    |> List.flatten
  end


  def add_index(bitfield, piece_index) do
    byte_index = div(piece_index, 8)
    byte_offset = rem(piece_index, 8)
    <<before :: bytes-size(byte_index), current_value, rest :: binary>> = bitfield
    new_value = Bitwise.band(current_value, Bitwise.<<<(1, 7 - byte_offset))
    <<before :: binary, new_value, rest :: binary>>
  end
end
