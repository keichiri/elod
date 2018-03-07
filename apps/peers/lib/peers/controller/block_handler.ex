defmodule Peers.Controller.BlockHandler do
  @moduledoc """
  Responsible for splitting pieces into blocks, tracking which blocks are missing,
  scheduling given blocks, and composing pieces from blocks once all blocks are
  completed.

  Used by PeerController, to abstract away keeping track of individual blocks.

  Responsibilities:
    1. tracking the state of pieces - how many blocks are left
    2. queueing blocks to be downloaded by priority
    3. tracking requested blocks
    4. tracking downloaded blocks
    5. composing pieces once all blocks are downloaded

  NOTE - not sure if this module should be split into two - one to track missing blocks
  and to queue, another one to manage/throttle downloads
  """

  defstruct queue: :queue.new(),
            pieces: %{},
            missing: %{},
            downloaded: %{},
            requested: %{}

  alias Peers.Controller.BlockHandler, as: BlockHandler

  @max_queue_length 100
  @max_requested_size 200
  @seconds_until_stale 60


  def new() do
    %BlockHandler{}
  end


  @doc """
  Adds new piece to be downloaded.

  Slices the piece into blocks and populates appropriate structures
  """
  def add_piece(
    block_handler = %{pieces: pieces, missing: missing},
    piece = %{index: index}
  ) do
    blocks = Core.Piece.split(piece)
    new_missing = for block = %{offset: offset, length: length} <- blocks, into: missing do
      {{index, offset, length}, {block, 0}}
    end
    piece_record = {piece, length(blocks)}
    new_pieces = Map.put(pieces, index, piece_record)
    %{block_handler | pieces: new_pieces, missing: new_missing}
  end


  @doc """
  Gets up to $count blocks, sorted by priority.

  These blocks are to be requested from peer, so they are added to requested
  section, in order to verify any incoming blocks

  ## Returns:
    - {blocks, new_block_handler}
  """
  def schedule_blocks(
    block_handler = %{queue: queue, missing: missing, requested: requested},
    count \\ 20
  ) do
    requested = if map_size(requested) >= @max_requested_size do
      purge_older_requested(requested)
    else
      requested
    end
    space_left = @max_requested_size - map_size(requested)
    count = min(space_left, count)
    {queue, missing} = if :queue.len(queue) < count do
      fill_queue(queue, requested, missing)
    else
      {queue, missing}
    end
    count = if count > :queue.len(queue) do
      :queue.len(queue)
    else
      count
    end
    {out, new_queue} = :queue.split(count, queue)
    out = :queue.to_list(out)
    now = :os.system_time(:seconds)

    ## NOTE - doesn't take into account if the block is already requested
    new_requested = Enum.reduce(
      out,
      requested,
      fn block = %{index: index, offset: offset, length: length}, requested_acc ->
        Map.put(requested_acc, {index, offset, length}, now)
      end
    )
    new_block_handler = %{block_handler | requested: new_requested,
                                          missing: missing,
                                          queue: new_queue}
    {out, new_block_handler}
  end


  defp purge_older_requested(requested) do
    now = :os.system_time(:seconds)
    requested
    |> Enum.reject(fn {block, request_ts} ->
      now - request_ts > @seconds_until_stale
    end)
    |> Enum.into(%{})
  end


  @doc """
  Processes freshly downloaded block, verifying that it is valid (exists in missing),
  moving it to downloaded.
  If it was the very last block for given piece, composes the piece and returns its

  ## Returns:
    - {:ok, new_block_handler}: for valid, not-last block
    - {:ok, piece, new_block_handler}: for valid, last block
    - {:error, :block_not_requested}
  """
  def add_downloaded_block(
    block_handler = %{queue: queue, missing: missing, requested: requested,
                      downloaded: downloaded, pieces: pieces},
    new_block = %{index: index, offset: offset, data: data}
  ) do
    block_key = {index, offset, byte_size(data)}
    case Map.pop(requested, block_key) do
      {nil, _} ->
        {:error, :block_not_requested}

      {_, new_requested} ->
        new_missing = Map.delete(missing, block_key)
        {piece, missing} = Map.get(pieces, index)
        new_queue = remove_block_from_queue(queue, new_block)

        if missing == 1 do
          {already_downloaded, new_downloaded} = Map.pop(downloaded, index)
          piece_data = compose_blocks([new_block | already_downloaded])
          completed_piece = %{piece | data: piece_data}
          new_pieces = Map.delete(pieces, index)
          new_block_handler = %{block_handler | pieces: new_pieces,
                                                missing: new_missing,
                                                downloaded: new_downloaded,
                                                requested: new_requested,
                                                queue: new_queue}
          {:ok, new_block_handler, completed_piece}
        else
          new_pieces = Map.put(pieces, index, {piece, missing - 1})
          new_downloaded = Map.update(downloaded, index, [new_block], fn already_downloaded ->
            [new_block | already_downloaded]
          end)
          new_block_handler = %{block_handler | pieces: new_pieces,
                                                missing: new_missing,
                                                downloaded: new_downloaded,
                                                requested: new_requested,
                                                queue: new_queue}
          {:ok, new_block_handler}
        end
    end
  end


  @doc """
  Called whenever one PeerController finishes a piece, and the others are to cancel.
  Makes sure the queue is purged, and all the structures are updated accordingly.

  Needs to return blocks already requested (but not received) for given piece,
  to send cancel messages appropriately.

  ## Returns:
    {requested_blocks, new_block_handler}
  """
  def cancel_piece(
    block_handler = %{pieces: pieces, downloaded: downloaded, requested: requested,
                      missing: missing, queue: queue},
    index
  ) do
    new_queue = remove_piece_from_queue(queue, index)
    new_pieces = Map.delete(pieces, index)
    new_downloaded = Map.delete(downloaded, index)

    requested_blocks =
      requested
      |> Map.keys
      |> Enum.filter(fn {piece_index, _offset, _length} -> piece_index == index end)
    new_requested = Map.drop(requested, requested_blocks)

    new_missing =
      missing
      |> Enum.reject(fn {_key, {%{index: piece_index}, _last_queue_ts}} ->
        piece_index == index
      end)
      |> Enum.into(%{})

    new_block_handler = %{block_handler | queue: new_queue,
                                          pieces: new_pieces,
                                          downloaded: new_downloaded,
                                          requested: new_requested,
                                          missing: new_missing}
    {requested_blocks, new_block_handler}
  end


  defp remove_piece_from_queue(queue, index) do
    queue
    |> :queue.to_list
    |> Enum.reject(fn %{index: index2} -> index == index2 end)
    |> :queue.from_list
  end


  defp remove_block_from_queue(queue, %{index: index, offset: offset}) do
    queue
    |> :queue.to_list
    |> Enum.reject(fn %{index: index2, offset: offset2} ->
      index == index2 and offset == offset2
    end)
    |> :queue.from_list
  end


  defp compose_blocks(blocks) do
    blocks
    |> Enum.sort(fn %{offset: offset1}, %{offset: offset2} ->
      offset1 <= offset2
    end)
    |> Stream.map(fn %{data: data} -> data end)
    |> Enum.join
  end


  @doc """
  Fills queue to up to @max_queue_length size.

  Blocks are added to queue with respect to the previous time they were enqueued -
  the oldest one is the one with the biggest priority.

  Blocks are updated with the new queue timestamp.

  TODO - consider giving highest priority to blocks whose piece has below
  10% of missing blocks for example

  ## Returns:
    {new_queue, new_blocks}
  """
  defp fill_queue(queue, requested_blocks, missing_blocks) do
    needed = @max_queue_length - :queue.len(queue)
    now = :os.system_time(:seconds)

    picked_blocks =
      missing_blocks
      |> Stream.reject(fn {_key, {block, ts}} ->
        now - ts < 5000 or Map.has_key?(requested_blocks, block)
      end)
      |> Enum.sort(fn {_key1, {_block1, ts1}}, {_key2, {_block2, ts2}} ->
        ts1 <= ts2
      end)
      |> Stream.map(fn {_key, {block, _ts}} -> block end)
      |> Enum.take(needed)

    new_missing_blocks = Enum.reduce(
      picked_blocks,
      missing_blocks,
      fn block = %{index: index, offset: offset, length: length}, block_acc ->
        Map.put(block_acc, {index, offset, length}, {block, now})
      end
    )
    new_queue = Enum.reduce(
      picked_blocks,
      queue,
      fn block, queue_acc ->
        :queue.in(block, queue_acc)
      end
    )
    {new_queue, new_missing_blocks}
  end
end
