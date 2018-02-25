defmodule Peers.PWP do
  @moduledoc """
  Implementation of Peer Wire Protocol.

  Contains encoding, decoding and validation of handshakes and regular messages.

  The representation of PWP messages is not abstracted away.
  For basic messages, atoms are used. For complex messages, tuples are used.
  Other variant would be to provide API for creating each type of message, but
  it complicates things unnecessarily, since messages are very simple.
  """


  def encode_handshake(info_hash, peer_id)
    when byte_size(info_hash) == 20 and byte_size(peer_id) == 20 do
    <<19,
      "BitTorrent protocol",
      0, 0, 0, 0, 0, 0, 0, 0,
      info_hash :: bytes-size(20),
      peer_id :: bytes-size(20)>>
  end


  def decode_handshake(<<
    19,
    "BitTorrent protocol",
    _ :: bytes-size(8),
    info_hash :: bytes-size(20),
    peer_id :: bytes-size(20)
  >>) do
    {:ok, {info_hash, peer_id}}
  end
  def decode_handshake(data) when byte_size(data) == 68 do
    {:error, :invalid_content}
  end
  def decode_handshake(_data) do
    {:error, :invalid_length}
  end


  def encode(:keep_alive), do: <<0 :: big-integer-size(32)>>
  def encode(:choke), do: <<1 :: big-integer-size(32), 0>>
  def encode(:unchoke), do: <<1 :: big-integer-size(32), 1>>
  def encode(:interested), do: <<1 :: big-integer-size(32), 2>>
  def encode(:uninterested), do: <<1 :: big-integer-size(32), 3>>
  def encode({:have, index}) do
    <<5 :: big-integer-size(32),
      4,
      index :: big-integer-size(32)>>
  end
  def encode({:bitfield, bitfield}) do
    len = byte_size(bitfield) + 1
    <<len :: big-integer-size(32),
      5,
      bitfield :: binary>>
  end
  def encode({:request, index, offset, length}) do
    <<13 :: big-integer-size(32),
      6,
      index :: big-integer-size(32),
      offset :: big-integer-size(32),
      length :: big-integer-size(32)>>
  end
  def encode({:piece, index, offset, data}) do
    len = 9 + byte_size(data)
    <<len :: big-integer-size(32),
      7,
      index :: big-integer-size(32),
      offset :: big-integer-size(32),
      data :: binary>>
  end
  def encode({:cancel, index, offset, length}) do
    <<13 :: big-integer-size(32),
      8,
      index :: big-integer-size(32),
      offset :: big-integer-size(32),
      length :: big-integer-size(32)>>
  end


  @doc """
  Attempts to decode a single PWP message from binary input.
  Expects that message has been chunked from binary stream properly, meaning
  that the length is valid.

  NOTE - if necessary, improve error output, to atleast specify type of message
  that was badly formatted. But PWP states that if any message is badly formatted,
  connection should be dropped.
  """
  def decode(<<0 :: big-integer-size(32)>>), do: {:ok, :keep_alive}
  def decode(<<1 :: big-integer-size(32), 0>>), do: {:ok, :choke}
  def decode(<<1 :: big-integer-size(32), 1>>), do: {:ok, :unchoke}
  def decode(<<1 :: big-integer-size(32), 2>>), do: {:ok, :interested}
  def decode(<<1 :: big-integer-size(32), 3>>), do: {:ok, :uninterested}
  def decode(<<
    5 :: big-integer-size(32),
    4,
    index :: big-integer-size(32)
  >>) do
    {:ok, {:have, index}}
  end
  def decode(<<
    len :: big-integer-size(32),
    5,
    bitfield :: binary
  >>) when byte_size(bitfield) == len - 1 do
    {:ok, {:bitfield, bitfield}}
  end
  def decode(<<
    13 :: big-integer-size(32),
    6,
    index :: big-integer-size(32),
    offset :: big-integer-size(32),
    length :: big-integer-size(32)
  >>) do
    {:ok, {:request, index, offset, length}}
  end
  def decode(<<
    len :: big-integer-size(32),
    7,
    index :: big-integer-size(32),
    offset :: big-integer-size(32),
    block_data :: binary
  >>) when byte_size(block_data) == len - 9 do
    {:ok, {:piece, index, offset, block_data}}
  end
  def decode(<<
    13 :: big-integer-size(32),
    8,
    index :: big-integer-size(32),
    offset :: big-integer-size(32),
    length :: big-integer-size(32)
  >>) do
    {:ok, {:cancel, index, offset, length}}
  end
  def decode(_bin), do: {:error, :invalid_content}


  @doc """
  Alternative API for decoding. Should return one or more messages contained in
  binary input, as well as remaining output to be buffered.

  ## Returns:
    - {:ok, messages, leftover}
    - {:error, reason}
  """
  def decode_messages(bin) do
    decode_messages(bin, [])
  end

  defp decode_messages(
    binary = <<length :: big-integer-size(32), rest :: binary>>,
    messages
  ) when byte_size(rest) < length do
    {:ok, Enum.reverse(messages), binary}
  end
  defp decode_messages(
    bin = <<length :: big-integer-size(32), _ :: bytes-size(length), rest :: binary>>,
    messages
  ) do
    whole_message = String.slice(bin, 0, length + 4)

    case decode(whole_message) do
      {:ok, message} ->
        decode_messages(rest, [message | messages])

      {:error, reason} ->
        IO.puts "Failed to decode. Current messages: #{inspect messages}. Whole message: #{inspect whole_message}"
        {:error, reason}
    end
  end
  defp decode_messages(binary, messages) when byte_size(binary) < 4 do
    {:ok, Enum.reverse(messages), binary}
  end
end
