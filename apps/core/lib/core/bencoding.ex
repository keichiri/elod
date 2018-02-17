defmodule Core.Bencoding do
  @doc """
  Performs the decoding of binary input according to the bencoding spec.

  ## Returns:
    {:ok, decoded_item}
    {:error, :partial_decode} -
      when input is only partially decoded
    {:error, reason} -
      when input is badly formed. Reason describes why the
      decoding failed. Can be either tuple or string, depending on how much
      information it carries.
  """
  def decode(binary) when is_binary(binary) do
    try do
      bdecode(binary)
    # catch
    #   _, reason -> {:error, reason}
    else
      {decoded_item, <<>>} ->
        {:ok, decoded_item}

      {_decoded_item, _leftover} ->
        {:error, :partial_decode}
    end
  end


  defp bdecode(<<"i", bin :: binary>>) do
    bdecode_integer(bin)
  end
  defp bdecode(<<byte, _ :: binary>> = bin) when byte in ?0..?9 do
    bdecode_string(bin)
  end
  defp bdecode(<<"l", bin :: binary>>) do
    bdecode_list(bin)
  end
  defp bdecode(<<"d", bin :: binary>>) do
    bdecode_map(bin)
  end
  defp bdecode(<<byte, _ :: binary>>), do: throw("Invalid item start byte: #{byte}")


  defp bdecode_integer(bin) do
    case String.split(bin, "e", parts: 2) do
      [integer_string, rest] ->
        {String.to_integer(integer_string), rest}

      [_] ->
        throw("Integer end not found")
    end
  end


  defp bdecode_string(bin) do
    case String.split(bin, ":", parts: 2) do
      [integer_string, bin2] ->
        string_length = String.to_integer(integer_string)

        if byte_size(bin2) >= string_length do
          String.split_at(bin2, string_length)
        else
          throw("Invalid string length: #{string_length}.Remaining length: #{byte_size(bin2)}")
        end

      [_] ->
        throw("String end not found")
    end
  end


  defp bdecode_list(bin, items \\ [])
  defp bdecode_list(<<"e", rest :: binary>>, items) do
    {Enum.reverse(items), rest}
  end
  defp bdecode_list(bin, items) do
    {item, bin2} = bdecode(bin)
    bdecode_list(bin2, [item | items])
  end


  defp bdecode_map(bin, items \\ %{})
  defp bdecode_map(<<"e", rest :: binary>>, items), do: {items, rest}
  defp bdecode_map(bin, items) do
    {key, bin2} = bdecode_string(bin)
    {value, bin3} = bdecode(bin2)
    bdecode_map(bin3, Map.put(items, key, value))
  end


  @doc """
  Performs encoding of input item according to the bencoding spec

  ## Returns:
    {:ok, encoded_item}
    {:error, :invalid_item_type} - when input contains unsupported types
  """
  def encode(item) do
    try do
      bencode(item)
    catch
      _, reason -> {:error, reason}
    else
      item -> {:ok, item}
    end
  end

  defp bencode(item) when is_integer(item), do: bencode_integer(item)
  defp bencode(item) when is_binary(item), do: bencode_string(item)
  defp bencode(item) when is_list(item), do: bencode_list(item)
  defp bencode(item) when is_map(item), do: bencode_map(item)
  defp bencode(_), do: throw(:invalid_item_type)

  defp bencode_integer(int), do: "i#{int}e"

  defp bencode_string(string), do: "#{byte_size(string)}:#{string}"

  defp bencode_list(list) do
    encoded_pieces = Enum.reduce(list, ["l"], fn item, acc_encoded ->
      encoded_item = bencode(item)
      [encoded_item | acc_encoded]
    end)

    ["e" | encoded_pieces]
    |> Enum.reverse
    |> List.to_string
  end

  defp bencode_map(map) do
    encoded_pieces = Enum.reduce(map, ["d"], fn {k, v}, acc_encoded ->
      encoded_pair = bencode_string(k) <> bencode(v)
      [encoded_pair | acc_encoded]
    end)

    ["e" | encoded_pieces]
    |> Enum.reverse
    |> List.to_string
  end
end
