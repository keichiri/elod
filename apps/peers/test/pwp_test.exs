defmodule Peers.Test.PWP do
  use ExUnit.Case

  alias Peers.PWP, as: PWP

  test "handshake encoding" do
    peer_id = for _ <- 0..19, into: <<>>, do: <<1>>
    info_hash = for _ <- 0..19, into: <<>>, do: <<2>>

    handshake = PWP.encode_handshake(info_hash, peer_id)

    assert handshake ==
      <<19, "BitTorrent protocol", 0, 0, 0, 0, 0, 0, 0, 0, info_hash :: binary, peer_id :: binary>>
  end


  test "handshake decoding" do
    info_hash = "11111111111111111111"
    peer_id = "22222222222222222222"
    valid_handshake =
      <<19, "BitTorrent protocol", 0,0,0,0,0,0,0,0, info_hash :: binary, peer_id :: binary>>

    assert PWP.decode_handshake(valid_handshake) == {:ok, {info_hash, peer_id}}

    invalid_handshakes = [
      <<18, "BitTorrent protocol", 0,0,0,0,0,0,0,0, info_hash :: binary, peer_id :: binary>>,
      <<19, "BitTorrent Protocol", 0,0,0,0,0,0,0,0, info_hash :: binary, peer_id :: binary>>,
      <<19, "BitTorrent protocol", 0,0,0,0,0,0,0,0, info_hash :: binary, peer_id :: binary, 1>>,
      <<19, "BitTorrent protocol2", 0,0,0,0,0,0,0,0, info_hash :: binary, peer_id :: binary>>,
    ]

    Enum.each(invalid_handshakes, fn invalid_handshake ->
      {res, _} = PWP.decode_handshake(invalid_handshake)
      assert res == :error
    end)
  end


  test "message encoding" do
    pairs = [
      {:keep_alive, <<0 :: big-integer-size(32)>>},
      {:choke, <<1 :: big-integer-size(32), 0>>},
      {:unchoke, <<1 :: big-integer-size(32), 1>>},
      {:interested, <<1 :: big-integer-size(32), 2>>},
      {:uninterested, <<1 :: big-integer-size(32), 3>>},
      {{:have, 1000}, <<5 :: big-integer-size(32), 4, 1000 :: big-integer-size(32)>>},
      {{:bitfield, "test_bitfield"}, <<14 :: big-integer-size(32), 5, "test_bitfield">>},
      {
        {:request, 1000, 2000, 3000},
        <<13 :: big-integer-size(32),
          6,
          1000 :: big-integer-size(32),
          2000 :: big-integer-size(32),
          3000 :: big-integer-size(32)>>
      },
      {
        {:piece, 1000, 10, "test_block"},
        <<19 :: big-integer-size(32),
          7,
          1000 :: big-integer-size(32),
          10 :: big-integer-size(32),
          "test_block">>
      },
      {
        {:cancel, 1000, 2000, 3000},
        <<13 :: big-integer-size(32),
          8,
          1000 :: big-integer-size(32),
          2000 :: big-integer-size(32),
          3000 :: big-integer-size(32)>>
      }
    ]

    Enum.each(pairs, fn {input, expected_output} ->
      output = PWP.encode(input)
      assert expected_output == output
    end)
  end


  test "valid message decoding" do
    valid_pairs = [
      {:keep_alive, <<0 :: big-integer-size(32)>>},
      {:choke, <<1 :: big-integer-size(32), 0>>},
      {:unchoke, <<1 :: big-integer-size(32), 1>>},
      {:interested, <<1 :: big-integer-size(32), 2>>},
      {:uninterested, <<1 :: big-integer-size(32), 3>>},
      {{:have, 1000}, <<5 :: big-integer-size(32), 4, 1000 :: big-integer-size(32)>>},
      {{:bitfield, "test_bitfield"}, <<14 :: big-integer-size(32), 5, "test_bitfield">>},
      {
        {:request, 1000, 2000, 3000},
        <<13 :: big-integer-size(32),
          6,
          1000 :: big-integer-size(32),
          2000 :: big-integer-size(32),
          3000 :: big-integer-size(32)>>
      },
      {
        {:piece, 1000, 10, "test_block"},
        <<19 :: big-integer-size(32),
          7,
          1000 :: big-integer-size(32),
          10 :: big-integer-size(32),
          "test_block">>
      },
      {
        {:cancel, 1000, 2000, 3000},
        <<13 :: big-integer-size(32),
          8,
          1000 :: big-integer-size(32),
          2000 :: big-integer-size(32),
          3000 :: big-integer-size(32)>>
      }
    ]

    Enum.each(valid_pairs, fn {expected_output, input} ->
      assert PWP.decode(input) == {:ok, expected_output}
    end)
  end


  # TODO - add more inputs
  test "invalid message decoding" do
    invalid_inputs = [
      <<0 :: big-integer-size(32), 0>>,
      <<1 :: big-integer-size(32), 10>>,
      <<1 :: big-integer-size(32), 5, 6>>,
      <<2 :: big-integer-size(32), 5>>,
      <<5 :: big-integer-size(32), 1000, 1000 :: big-integer-size(32)>>,
      <<14 :: big-integer-size(32), 5, "test_bitfielda">>,
      <<14 :: big-integer-size(32), 6, "test_bitfield">>,
      <<13 :: big-integer-size(32),
        6,
        1000 :: big-integer-size(32),
        2000 :: big-integer-size(32),
        3000 :: big-integer-size(16)>>,
      <<19 :: big-integer-size(32),
        7,
        1000 :: big-integer-size(32),
        10 :: big-integer-size(32),
        "test_block", 0>>,
      <<13 :: big-integer-size(32),
        8,
        1000 :: big-integer-size(32),
        2000 :: big-integer-size(32),
        3000 :: big-integer-size(32), 0>>
    ]

    Enum.each(invalid_inputs, fn invalid_input ->
      {res, _} = PWP.decode(invalid_input)
      assert res == :error
    end)
  end


  test "decode valid messages" do
    messages = [
      {:have, 5},
      {:bitfield, "bitfield_data"},
      :choke,
      {:request, 5, 10, 15},
      :interested,
      {:cancel, 5, 10, 15},
      :uninterested,
      {:piece, 5, 10, "test_block"},
      {:have, 30},
      :keep_alive,
      :unchoke,
      {:request, 100, 200, 300}
    ]
    encoded_messages =
      messages
      |> Enum.map(&PWP.encode/1)
      |> Enum.join

    encoded_messages = encoded_messages <> "leftover"

    {:ok, decoded_messages, leftover} = PWP.decode_messages(encoded_messages)

    assert leftover == "leftover"
    assert decoded_messages == messages
  end
end
