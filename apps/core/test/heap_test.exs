defmodule Core.Test.Heap do
  use ExUnit.Case

  alias Core.Heap, as: Heap


  def cmp_fun({key1, value1}, {key2, value2}) do
    key1 <= key2
  end


  test "pop from empty" do
    heap = Heap.new(&cmp_fun/2)

    assert nil == Heap.pop(heap)
  end

  test "single item push/pop" do
    heap = Heap.new(&cmp_fun/2)

    heap = Heap.push(heap, {1, :foo})
    {item, heap} = Heap.pop(heap)

    assert {1, :foo} == item
    assert :nil == Heap.pop(heap)
  end

  test "multiple items push/pop evenly distributed" do
    heap = Heap.new(&cmp_fun/2)
    heap =
      heap
      |> Heap.push({1, "item1"})
      |> Heap.push({10, "item2"})
      |> Heap.push({7, "item3"})
      |> Heap.push({3, "item4"})
      |> Heap.push({0, "item5"})
      |> Heap.push({11, "item6"})
      |> Heap.push({9, "item7"})

    {item, heap} = Heap.pop(heap)
    assert {0, "item5"} == item
    {item, heap} = Heap.pop(heap)
    assert {1, "item1"} == item
    {item, heap} = Heap.pop(heap)
    assert {3, "item4"} == item
    {item, heap} = Heap.pop(heap)
    assert {7, "item3"} == item
    {item, heap} = Heap.pop(heap)
    assert {9, "item7"} == item
    {item, heap} = Heap.pop(heap)
    assert {10, "item2"} == item
    {item, heap} = Heap.pop(heap)
    assert {11, "item6"} == item
    assert nil == Heap.pop(heap)
  end


  test "multiple items push/pop reducing constantly" do
    heap = Heap.new(&cmp_fun/2)
    heap = 100..1 |> Enum.reduce(heap, fn item, heap_acc ->
      Heap.push(heap_acc, {item, "item#{item}"})
    end)

    heap = 1..50 |> Enum.reduce(heap, fn i, heap_acc ->
      {item, heap} = Heap.pop(heap_acc)
      assert item == {i, "item#{i}"}
      heap
    end)

    heap = 150..101 |> Enum.reduce(heap, fn item, heap_acc ->
      Heap.push(heap_acc, {item, "item#{item}"})
    end)

    heap = 51..150 |> Enum.reduce(heap, fn i, heap_acc ->
      {item, heap} = Heap.pop(heap_acc)
      assert item == {i, "item#{i}"}
      heap
    end)

    assert nil == Heap.pop(heap)
  end


  test "multiple items push/pop several times randomly" do
    heap = Heap.new(&cmp_fun/2)
    heap =
      heap
      |> Heap.push({1, "item1"})
      |> Heap.push({10, "item2"})
      |> Heap.push({7, "item3"})
      |> Heap.push({3, "item4"})
      |> Heap.push({0, "item5"})

    {item, heap} = Heap.pop(heap)
    assert {0, "item5"} == item
    {item, heap} = Heap.pop(heap)
    assert {1, "item1"} == item
    {item, heap} = Heap.pop(heap)
    assert {3, "item4"} == item

    heap =
      heap
      |> Heap.push({11, "item6"})
      |> Heap.push({9, "item7"})
      |> Heap.push({100, "item8"})
      |> Heap.push({2, "item9"})


    {item, heap} = Heap.pop(heap)
    assert {2, "item9"} == item
    {item, heap} = Heap.pop(heap)
    assert {7, "item3"} == item
    {item, heap} = Heap.pop(heap)
    assert {9, "item7"} == item
    {item, heap} = Heap.pop(heap)
    assert {10, "item2"} == item
    {item, heap} = Heap.pop(heap)
    assert {11, "item6"} == item
    {item, heap} = Heap.pop(heap)
    assert {100, "item8"} == item
    assert nil == Heap.pop(heap)
  end
end
