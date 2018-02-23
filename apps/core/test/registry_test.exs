defmodule Core.Registry.Test do
  use ExUnit.Case

  alias Core.Registry, as: Registry


  test "registering and retrieving" do
    pid = spawn(fn -> :timer.sleep(3) end)
    {:ok, registry} = Registry.start_link()

    Registry.register(:test, pid)
    retrieved_pid = Registry.whereis(:test)

    assert retrieved_pid == pid

    Process.exit(registry, :kill)
  end

  test "registering and deregistering" do
    pid = spawn(fn -> :timer.sleep(5) end)
    {:ok, registry} = Registry.start_link()

    Registry.register(:test, pid)
    retrieved_pid = Registry.whereis(:test)
    assert retrieved_pid == pid
    Registry.deregister(:test)
    retrieved_pid = Registry.whereis(:test)
    assert retrieved_pid == nil

    Process.exit(registry, :kill)
  end

  test "dead processes deregistration" do
    pid = spawn(fn -> :timer.sleep(500) end)
    {:ok, registry} = Registry.start_link()

    Registry.register(:test, pid)
    assert Registry.whereis(:test) == pid
    Process.exit(pid, :kill)
    :timer.sleep(1)
    assert Registry.whereis(:test) == nil

    Process.exit(registry, :kill)
  end

  test "multiple processes flow" do
    pid1 = spawn(fn -> :timer.sleep(5) end)
    pid2 = spawn(fn -> :timer.sleep(5) end)
    pid3 = spawn(fn -> :timer.sleep(5) end)
    {:ok, registry} = Registry.start_link()

    Registry.register(:test1, pid1)
    Registry.register(:test2, pid2)
    Registry.register(:test3, pid3)

    assert Registry.whereis(:test1) == pid1
    assert Registry.whereis(:test2) == pid2
    assert Registry.whereis(:test3) == pid3

    Process.exit(pid1, :kill)
    Registry.deregister(:test3)
    :timer.sleep(1)

    assert Registry.whereis(:test1) == nil
    assert Registry.whereis(:test2) == pid2
    assert Registry.whereis(:test3) == nil

    Process.exit(registry, :kill)
  end
end
