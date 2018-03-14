defmodule Core.Heap.Node do
  defstruct item: nil, left: nil, right: nil

  alias Core.Heap.Node, as: Node


  def new(item) do
    %Node{item: item}
  end

  def swap_item(node = %Node{item: item}, new_item) do
    {item, %{node | item: new_item}}
  end

  def add_left(node, item) do
    %{node | left: Node.new(item)}
  end

  def remove_left(node = %Node{left: %Node{item: left_item}}) do
    {left_item, %{node | left: nil}}
  end

  def add_right(node, item) do
    %{node | right: Node.new(item)}
  end

  def remove_right(node = %Node{right: %Node{item: right_item}}) do
    {right_item, %{node | right: nil}}
  end

  def maybe_swap_left(
    node = %Node{item: item, left: left = %Node{item: left_item}},
    compare_function
  ) do
    if compare_function.(left_item, item) do
      new_left = %{left | item: item}
      %{node | left: new_left, item: left_item}
    else
      node
    end
  end
  def maybe_swap_right(
    node = %Node{item: item, right: right = %Node{item: right_item}},
    compare_function
  ) do
    if compare_function.(right_item, item) do
      new_right = %{right | item: item}
      %{node | right: new_right, item: right_item}
    else
      node
    end
  end


  def swap_with_smaller_child(
    node = %Node{left: left = %Node{item: left_item}, right: nil, item: item},
    compare_function
  ) do
    if compare_function.(left_item, item) do
      {:left, %{node | left: %{left | item: item}, item: left_item}}
    else
      nil
    end
  end
  def swap_with_smaller_child(
    node = %Node{left: left = %Node{item: left_item}, right: right = %Node{item: right_item}, item: item},
    compare_function
  ) do
    if compare_function.(left_item, right_item) do
      if compare_function.(left_item, item) do
        new_left = %{left | item: item}
        {:left, %{node | left: new_left, item: left_item}}
      else
        :nil
      end
    else
      if compare_function.(right_item, item) do
        new_right = %{right | item: item}
        {:right, %{node | right: new_right, item: right_item}}
      else
        :nil
      end
    end
  end
end


defmodule Core.Heap do
  @moduledoc """
  Simple heap implementation. Not optimized.

  TODO - benchmark and improve
  """

  defstruct root: nil, cmp_fun: nil, size: nil

  alias Core.Heap, as: Heap
  alias Core.Heap.Node, as: Node


  def new(cmp_fun) do
    %Heap{cmp_fun: cmp_fun}
  end

  def pop(heap = %{root: nil}) do
    nil
  end
  def pop(heap = %{root: root = %{item: item, left: nil, right: nil}}) do
    {item, %{heap | root: nil, size: 0}}
  end
  def pop(heap = %{root: root, size: size, cmp_fun: cmp_fun}) do
    steps = calculate_steps(size)
    {last_item, new_root} = remove_last(root, steps)
    {first_item, new_root} = Node.swap_item(new_root, last_item)
    new_root = bubble_node_down(new_root, cmp_fun)
    {first_item, %{heap | size: size - 1, root: new_root}}
  end

  def push(heap = %{root: nil}, item) do
    %{heap | root: Node.new(item), size: 1}
  end
  def push(heap, item) do
    heap
    |> add_to_end(item)
    |> bubble_up
  end

  defp add_to_end(heap = %{root: root, size: size}, item) do
    new_size = size + 1
    steps = calculate_steps(new_size)
    new_root = node_add(root, steps, item)
    %{heap | root: new_root, size: new_size}
  end


  defp node_add(node, [0], item) do
    Node.add_left(node, item)
  end
  defp node_add(node, [1], item) do
    Node.add_right(node, item)
  end
  defp node_add(node = %{left: left}, [0 | steps], item) do
    %{node | left: node_add(left, steps, item)}
  end
  defp node_add(node = %{right: right}, [1 | steps], item) do
    %{node | right: node_add(right, steps, item)}
  end


  def calculate_steps(size) do
    calculate_steps(size, [])
  end
  def calculate_steps(size, steps) when size <= 1 do
    steps
  end
  def calculate_steps(size, steps) do
    step = rem(size, 2)
    new_size = div(size, 2)
    calculate_steps(new_size, [step | steps])
  end


  defp bubble_up(heap = %{root: root, size: size, cmp_fun: cmp_fun}) do
    steps = calculate_steps(size)
    new_root = bubble_node_up(root, cmp_fun, steps)
    %{heap | root: new_root}
  end

  defp bubble_node_up(node = %{left: left}, cmp_fun, [0]) do
    Node.maybe_swap_left(node, cmp_fun)
  end
  defp bubble_node_up(node = %{right: right}, cmp_fun, [1]) do
    Node.maybe_swap_right(node, cmp_fun)
  end
  defp bubble_node_up(node = %{left: left}, cmp_fun, [0 | steps]) do
    node = %{node | left: bubble_node_up(left, cmp_fun, steps)}
    Node.maybe_swap_left(node, cmp_fun)
  end
  defp bubble_node_up(node = %{right: right}, cmp_fun, [1 | steps]) do
    node = %{node | right: bubble_node_up(right, cmp_fun, steps)}
    Node.maybe_swap_right(node, cmp_fun)
  end


  defp bubble_node_down(node = %{left: nil}, cmp_fun) do
    node
  end
  defp bubble_node_down(node, cmp_fun) do
    case Node.swap_with_smaller_child(node, cmp_fun) do
      {:left, new_node = %{left: left}} ->
        new_left = bubble_node_down(left, cmp_fun)
        %{new_node | left: new_left}

      {:right, new_node = %{right: right}} ->
        new_right = bubble_node_down(right, cmp_fun)
        %{new_node | right: new_right}

      :nil ->
        node
    end
  end

  defp remove_last(node, [0]) do
    Node.remove_left(node)
  end
  defp remove_last(node, [1]) do
    Node.remove_right(node)
  end
  defp remove_last(node = %{left: left}, [0 | steps]) do
    {last_item, new_left} = remove_last(left, steps)
    {last_item, %{node | left: new_left}}
  end
  defp remove_last(node = %{right: right}, [1 | steps]) do
    {last_item, new_right} = remove_last(right, steps)
    {last_item, %{node | right: new_right}}
  end
end
