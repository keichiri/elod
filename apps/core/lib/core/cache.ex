defmodule Core.Cache do
  @moduledoc """
  Simple LRU K-V cache for binaries, intended to store piece data.
  """

  defmodule Record do
    defstruct ticket: nil, data: nil

    def new(data, ticket) do
      %Record{ticket: ticket, data: data}
    end

    def retrieve_and_update_ticket(record = %{data: data}, ticket) do
      {data, %{record | ticket: ticket}}
    end
  end


  defstruct records: %{}, current_size: 0, max_size: nil, ticket: 0

  alias Core.Cache, as: Cache


  def new(max_size) do
    %Cache{max_size: max_size}
  end


  def add(cache = %{current_size: current_size, max_size: max}, key, data)
    when current_size >= max do
    add(purge(cache), key, data)
  end
  def add(cache, key, data) do
    new_record = Record.new(data, cache.ticket)
    %{cache | records: Map.put(cache.records, key, new_record),
              current_size: cache.current_size + byte_size(data),
              ticket: cache.ticket + 1}
  end


  def get(cache = %{records: records}, key) do
    case Map.get(records, key, nil) do
      nil -> nil
      record = %{data: data} ->
        new_record = Record.retrieve_and_update_ticket(record, cache.ticket)
        new_cache = %{cache | records: Map.put(records, key, new_record),
                              ticket: cache.ticket + 1}
        {data, new_cache}
    end
  end


  defp purge(cache = %{records: records}) do
    to_remove = round(map_size(records * 0.25))
    {oldest_keys, to_remove_size} =
      records
      |> Enum.sort(fn {key1, %{ticket: ticket1}}, {key2, %{ticket: ticket2}} ->
        ticket1 <= ticket2
      end)
      |> Enum.take(to_remove)
      |> Enum.reduce(
        {[], 0},
        fn key, %{data: data}, {keys_acc, size_acc} ->
          {[key | keys_acc], size_acc + byte_size(data)}
        end
      )
    %{cache | records: Map.drop(records, oldest_keys),
              current_size: cache.current_size - to_remove_size}
  end
end
