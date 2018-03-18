defmodule Core.Bitfield.Test do
  use ExUnit.Case

  alias Core.Bitfield, as: Bitfield


  test "valid bitfield" do
    pieces = for i <- 0..17, do: %{index: i}
    existing_pieces = MapSet.new([1, 4, 8, 11, 12, 16])
    expected_bitfield = <<64+8, 128+16+8, 128>>

    bitfield = Bitfield.create(pieces, existing_pieces)

    assert bitfield == expected_bitfield
  end


  test "get existing indexese" do
    bitfield = <<7, 4, 128>>

    indexes = Bitfield.get_existing_indexes(bitfield)

    assert indexes == [5,6,7,13,16]
  end
end
