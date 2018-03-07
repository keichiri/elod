defmodule Peers.Test.BlockHandler do
  use ExUnit.Case

  alias Peers.Controller.BlockHandler, as: BlockHandler


  test "add_piece" do
    block_handler = BlockHandler.new()
    piece = %{
      index: 1,
      length: 1000,
    }

    block_handler = BlockHandler.add_piece(block_handler, piece)

    assert block_handler.queue == :queue.new()
    assert block_handler.pieces == %{
      1 => {piece, 2}
    }
    assert block_handler.downloaded == %{}
    assert map_size(block_handler.missing) == 2
  end


  test "schedule_blocks if queue is large enough" do
    block_1 = %{index: 1, offset: 0, length: 2}
    block_2 = %{index: 1, offset: 2, length: 2}
    block_3 = %{index: 1, offset: 4, length: 2}
    block_4 = %{index: 1, offset: 6, length: 2}
    blocks = [block_1, block_2, block_3, block_4]
    missing = %{
      {1, 0, 2} => {block_1, 10},
      {1, 2, 2} => {block_2, 11},
      {1, 4, 2} => {block_3, 12},
      {1, 6, 2} => {block_4, 5},
    }
    block_handler = BlockHandler.new()
    block_handler = %{block_handler | queue: :queue.from_list(blocks),
                                      missing: missing}

    {blocks, block_handler} = BlockHandler.schedule_blocks(block_handler, 3)

    # Asserts that only exactly three blocks with oldest previous queue-ing ts were given
    # Asserts that the fourth one is still in queue
    # Asserts that all four have their queue timestamps updated
    assert blocks == [block_1, block_2, block_3]
    assert elem(block_handler.missing[{1, 0, 2}], 1) == 10
    assert elem(block_handler.missing[{1, 2, 2}], 1) == 11
    assert elem(block_handler.missing[{1, 4, 2}], 1) == 12
    assert elem(block_handler.missing[{1, 6, 2}], 1) == 5
    assert Map.has_key?(block_handler.requested, {1, 0, 2}) == true
    assert Map.has_key?(block_handler.requested, {1, 2, 2}) == true
    assert Map.has_key?(block_handler.requested, {1, 4, 2}) == true
    assert :queue.len(block_handler.queue) == 1
  end


  # Tests that requested block map is cleaned up
  # and that queue is shortened
  # and blocks from queue added to requested
  # and timestamps updated in missing blocks
  test "schedule_blocks if queue is large enough, if requested map too large" do
    block_1 = %{index: 1, offset: 0, length: 2}
    block_2 = %{index: 1, offset: 2, length: 2}
    block_3 = %{index: 1, offset: 4, length: 2}
    block_4 = %{index: 1, offset: 6, length: 2}
    blocks = [block_1, block_2, block_3, block_4]
    requested = for i <- 100..300, into: %{}, do: {{1, i * 2, 2}, 1000}
    missing = %{
      {1, 0, 2} => {block_1, 10},
      {1, 2, 2} => {block_2, 11},
      {1, 4, 2} => {block_3, 12},
      {1, 6, 2} => {block_4, 5},
    }
    block_handler = BlockHandler.new()
    block_handler = %{block_handler | queue: :queue.from_list(blocks),
                                      missing: missing,
                                      requested: requested}

    {blocks, block_handler} = BlockHandler.schedule_blocks(block_handler, 3)

    # Asserts that only exactly three blocks with oldest previous queue-ing ts were given
    # Asserts that the fourth one is still in queue
    # Asserts that all four have their queue timestamps updated
    assert blocks == [block_1, block_2, block_3]
    assert elem(block_handler.missing[{1, 0, 2}], 1) == 10
    assert elem(block_handler.missing[{1, 2, 2}], 1) == 11
    assert elem(block_handler.missing[{1, 4, 2}], 1) == 12
    assert elem(block_handler.missing[{1, 6, 2}], 1) == 5
    assert Map.has_key?(block_handler.requested, {1, 0, 2}) == true
    assert Map.has_key?(block_handler.requested, {1, 2, 2}) == true
    assert Map.has_key?(block_handler.requested, {1, 4, 2}) == true
    assert :queue.len(block_handler.queue) == 1
  end


  test "schedule_blocks if queue is empty, with missing pieces" do
    block_1 = %{index: 1, offset: 0, length: 2}
    block_2 = %{index: 1, offset: 2, length: 2}
    block_3 = %{index: 1, offset: 4, length: 2}
    block_4 = %{index: 1, offset: 6, length: 2}
    missing = %{
      {1, 0, 2} => {block_1, 10},
      {1, 2, 2} => {block_2, 11},
      {1, 4, 2} => {block_3, 12},
      {1, 6, 2} => {block_4, 5},
    }
    block_handler = BlockHandler.new()
    block_handler = %{block_handler | missing: missing}

    now = :os.system_time(:seconds)
    {blocks, block_handler} = BlockHandler.schedule_blocks(block_handler, 3)

    # Asserts that only exactly three blocks with oldest previous queue-ing ts were given
    # Asserts that the fourth one is still in queue
    # Asserts that all four have their queue timestamps updated
    assert blocks == [block_4, block_1, block_2]
    assert elem(block_handler.missing[{1, 0, 2}], 1) >= now
    assert elem(block_handler.missing[{1, 2, 2}], 1) >= now
    assert elem(block_handler.missing[{1, 4, 2}], 1) == now
    assert elem(block_handler.missing[{1, 6, 2}], 1) >= now
    assert Map.has_key?(block_handler.requested, {1, 0, 2}) == true
    assert Map.has_key?(block_handler.requested, {1, 2, 2}) == true
    assert Map.has_key?(block_handler.requested, {1, 4, 2}) == false
    assert Map.has_key?(block_handler.requested, {1, 6, 2}) == true
    assert :queue.len(block_handler.queue) == 1
  end


  test "schedule_blocks if queue is empty, without missing pieces" do
    block_handler = BlockHandler.new()

    {blocks, _} = BlockHandler.schedule_blocks(block_handler, 3)

    assert blocks == []
  end


  test "schedule_blocks if queue is empty, with missing pieces, with some blocks queued and some requested" do
    block_1 = %{index: 1, offset: 0, length: 2}
    block_2 = %{index: 1, offset: 2, length: 2}
    block_3 = %{index: 1, offset: 4, length: 2}
    block_4 = %{index: 1, offset: 6, length: 2}
    block_5 = %{index: 1, offset: 8, length: 2}
    now = :os.system_time(:seconds)
    missing = %{
      {1, 0, 2} => {block_1, 10},
      {1, 2, 2} => {block_2, now - 1},
      {1, 4, 2} => {block_3, now - 1},
      {1, 6, 2} => {block_4, 11},
      {1, 8, 2} => {block_5, now - 10}
    }
    requested = %{
      {1, 8, 2} => now - 10
    }
    block_handler = BlockHandler.new()
    block_handler = %{block_handler | missing: missing, requested: requested}

    {blocks, block_handler} = BlockHandler.schedule_blocks(block_handler, 3)

    # Asserts that only exactly three blocks with oldest previous queue-ing ts were given
    # Asserts that the fourth one is still in queue
    # Asserts that all four have their queue timestamps updated
    assert blocks == [block_1, block_4]
    assert elem(block_handler.missing[{1, 0, 2}], 1) >= now
    assert elem(block_handler.missing[{1, 2, 2}], 1) == now - 1
    assert elem(block_handler.missing[{1, 4, 2}], 1) == now - 1
    assert elem(block_handler.missing[{1, 6, 2}], 1) >= now
    assert Map.has_key?(block_handler.requested, {1, 0, 2}) == true
    assert Map.has_key?(block_handler.requested, {1, 2, 2}) == false
    assert Map.has_key?(block_handler.requested, {1, 4, 2}) == false
    assert Map.has_key?(block_handler.requested, {1, 6, 2}) == true
    assert Map.has_key?(block_handler.requested, {1, 8, 2}) == true
    assert :queue.len(block_handler.queue) == 0
  end


  # Tests that queue is purged appropriately,
  # block is removed from requested,
  # block is removed from missing
  # and block is added to downloaded
  test "add_downloaded_block if block is requested, but not last" do
    block_1 = %{index: 1, offset: 0, length: 2, data: nil}
    block_2 = %{index: 1, offset: 2, length: 2, data: nil}
    block_3 = %{index: 1, offset: 4, length: 2, data: nil}
    block_4 = %{index: 1, offset: 6, length: 2, data: nil}
    now = :os.system_time(:seconds)
    block_handler = BlockHandler.new()
    missing = %{
      {1, 0, 2} => {block_1, 10},
      {1, 2, 2} => {block_2, now - 1},
      {1, 4, 2} => {block_3, now - 1},
      {1, 6, 2} => {block_4, 5},
    }
    requested = %{
      {1, 4, 2} => now - 10
    }
    piece = %{index: 1, length: 2000}
    pieces = %{
      1 => {piece, 4}
    }
    queue = :queue.from_list([block_4, block_3])
    block_handler = %{block_handler | missing: missing,
                                      pieces: pieces,
                                      queue: queue,
                                      requested: requested}

    downloaded_block = %{index: 1, offset: 4, data: "dd"}
    {:ok, block_handler} = BlockHandler.add_downloaded_block(block_handler, downloaded_block)
    assert block_handler.pieces == %{
      1 => {piece, 3}
    }
    # Asserts it was removed from queue
    assert block_handler.queue == :queue.from_list([block_4])
    assert block_handler.missing == %{
      {1, 0, 2} => {block_1, 10},
      {1, 2, 2} => {block_2, now - 1},
      {1, 6, 2} => {block_4, 5},
    }
    assert block_handler.requested == %{}
    assert block_handler.downloaded == %{
      1 => [downloaded_block]
    }
  end

  test "add_downloaded_block if block is not requested" do
    block_handler = BlockHandler.new()

    {:error, reason} = BlockHandler.add_downloaded_block(block_handler, %{index: 1, offset: 2, data: "eee"})
    assert reason == :block_not_requested
  end


  test "add_downloaded_block if block is missing, and last" do
    ## NOTE - the logic inside the BlockHandler does not check the length of blocks
    block_1 = %{index: 1, offset: 0, length: 2, data: "aa"}
    block_2 = %{index: 1, offset: 2, length: 2, data: "bb"}
    block_3 = %{index: 1, offset: 4, length: 2, data: "cc"}
    block_4 = %{index: 1, offset: 6, length: 2}
    block_handler = BlockHandler.new()
    missing = %{
      {1, 6, 2} => {block_4, 5},
    }
    requested = %{
      {1, 6, 2} => 10000
    }
    piece = %{index: 1, length: 2000, data: nil}
    pieces = %{
      1 => {piece, 1}
    }
    downloaded = %{
      1 => [block_1, block_3, block_2]
    }
    queue = :queue.from_list([block_4])
    block_handler = %{block_handler | missing: missing,
                                      pieces: pieces,
                                      queue: queue,
                                      requested: requested,
                                      downloaded: downloaded}

    {:ok, block_handler, piece} = BlockHandler.add_downloaded_block(block_handler, %{index: 1, offset: 6, data: "dd"})
    assert block_handler.pieces == %{}
    assert block_handler.queue == :queue.new()
    assert block_handler.missing == %{}
    assert block_handler.downloaded == %{}
    assert block_handler.requested == %{}
    assert piece.data == "aabbccdd"
  end


  test "cancel_piece when piece has blocks in queue" do
    block_1 = %{index: 1, offset: 0, length: 2, data: "aa"}
    block_2 = %{index: 1, offset: 2, length: 2, data: "bb"}
    block_3 = %{index: 1, offset: 4, length: 2, data: "cc"}
    piece = %{index: 1, length: 2000, data: nil}
    block_handler = BlockHandler.new()
    pieces = %{
      1 => {piece, 1}
    }
    requested = %{
      {1, 4, 2} => 100000
    }
    missing = %{
      {1, 4, 2} => {block_3, 10000},
    }
    downloaded = %{
      1 => [block_1]
    }
    block_handler = %{block_handler | queue: :queue.from_list([block_2]),
                                      downloaded: downloaded,
                                      missing: missing,
                                      pieces: pieces,
                                      requested: requested}

    {requested_blocks, block_handler} = BlockHandler.cancel_piece(block_handler, 1)
    assert requested_blocks == [{1, 4, 2}]
    assert block_handler.queue == :queue.new()
    assert block_handler.pieces == %{}
    assert block_handler.missing == %{}
    assert block_handler.downloaded == %{}
    assert block_handler.requested == %{}
  end
end
