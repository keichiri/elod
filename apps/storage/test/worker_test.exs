defmodule Storage.Test.Worker do
  use ExUnit.Case

  alias Storage.Worker, as: Worker


  @test_path "/tmp/elod/test/storage"


  setup_all do
    if File.exists?(@test_path) do
      IO.puts "Need to delete"
    end
    :ok = File.mkdir_p!(@test_path)
    :ok
  end


  test "store piece" do
    content = "test_content"
    {:ok, worker} = Worker.start_link(@test_path)
    caller = self()
    callback = fn index ->
      send(caller, {:ok, self()})
    end

    Worker.store(worker, 1, content, callback)

    assert_receive({:ok, worker}, 1000)

    content = File.read!(Path.join(@test_path, "1.piece"))
    assert content == "test_content"
  end


  test "retrieve piece" do
    content = "test_content"
    :ok = File.write!(Path.join(@test_path, "2.piece"), content)
    {:ok, worker} = Worker.start_link(@test_path)
    caller = self()
    callback = fn index, content ->
      send(caller, {:ok, self(), content})
    end

    Worker.retrieve(worker, 2, callback)

    assert_receive({:ok, worker, "test_content"}, 1000)
  end


  test "store and retrieve" do
    content = "test_content"
    {:ok, worker} = Worker.start_link(@test_path)
    store_callback = fn index -> nil end
    Worker.store(worker, 1, content, store_callback)
    caller = self()
    retrieve_callback = fn index, content ->
      send(caller, {:ok, self(), index, content})
    end
    Worker.retrieve(worker, 1, retrieve_callback)

    assert_receive({:ok, ^worker, 1, "test_content"}, 1000)
  end


  test "compose files" do
    files = [
      %Core.File{length: 10, path: "dir/file1.txt"},
      %Core.File{length: 2, path: "dir/file2.txt"},
      %Core.File{length: 8, path: "dir/file3.txt"},
      %Core.File{length: 10, path: "dir/file4.txt"},
      %Core.File{length: 3, path: "dir/file5.txt"},
    ]
    piece_contents = for i <- 0..3, do: for _ <- 0..6, into: <<>>, do: <<i>>
    piece_contents = List.insert_at(piece_contents, -1, <<4,4,4,4,4>>)
    piece_contents
    |> Enum.with_index
    |> Enum.each(fn {content, index} ->
      File.write!(Path.join(@test_path, "#{index}.piece"), content)
    end)
    {:ok, worker} = Worker.start_link(@test_path)
    pid = self()
    callback = fn path ->
      send(pid, {:ok, self(), path})
    end

    Worker.compose(worker, files, callback)

    assert_receive({:ok, worker, @test_path})
    assert File.read!(Path.join(@test_path, "dir/file1.txt")) == <<0,0,0,0,0,0,0,1,1,1>>
    assert File.read!(Path.join(@test_path, "dir/file2.txt")) == <<1,1>>
    assert File.read!(Path.join(@test_path, "dir/file3.txt")) == <<1,1,2,2,2,2,2,2>>
    assert File.read!(Path.join(@test_path, "dir/file4.txt")) == <<2,3,3,3,3,3,3,3,4,4>>
    assert File.read!(Path.join(@test_path, "dir/file5.txt")) == <<4,4,4>>
  end


  test "complete test" do
    files = [
      %Core.File{length: 10, path: "dir/file1.txt"},
      %Core.File{length: 2, path: "dir/file2.txt"},
      %Core.File{length: 8, path: "dir/file3.txt"},
      %Core.File{length: 10, path: "dir/file4.txt"},
      %Core.File{length: 3, path: "dir/file5.txt"},
    ]
    piece_contents = for i <- 0..3, do: for _ <- 0..6, into: <<>>, do: <<i>>
    piece_contents = List.insert_at(piece_contents, -1, <<4,4,4,4,4>>)
    pid = self()

    {:ok, worker} = Worker.start_link(@test_path)

    # Storing pieces
    store_callback = fn index ->
      send(pid, {:ok, self(), index})
    end
    piece_contents
    |> Enum.with_index
    |> Enum.each(fn {content, index} ->
      Worker.store(worker, index, content, store_callback)
    end)
    Enum.each(0..4, fn i -> assert_receive({:ok, worker, i}, 100) end)

    # Composing files
    compose_callback = fn path ->
      send(pid, {:ok, self(), path})
    end
    Worker.compose(worker, files, compose_callback)
    assert_receive({:ok, worker, @test_path}, 100)
    assert File.read!(Path.join(@test_path, "dir/file1.txt")) == <<0,0,0,0,0,0,0,1,1,1>>
    assert File.read!(Path.join(@test_path, "dir/file2.txt")) == <<1,1>>
    assert File.read!(Path.join(@test_path, "dir/file3.txt")) == <<1,1,2,2,2,2,2,2>>
    assert File.read!(Path.join(@test_path, "dir/file4.txt")) == <<2,3,3,3,3,3,3,3,4,4>>
    assert File.read!(Path.join(@test_path, "dir/file5.txt")) == <<4,4,4>>

    # Retrieving pieces
    retrieve_callback = fn index, data ->
      send(pid, {:ok, self(), index, data})
    end
    assert Process.alive?(worker)
    IO.puts "Gonna order to retrieve"
    Enum.each(0..4, fn i -> Worker.retrieve(worker, i, retrieve_callback) end)
    assert_receive({:ok, worker, 0, <<0,0,0,0,0,0,0>>}, 100)
    assert_receive({:ok, worker, 1, <<1,1,1,1,1,1,1>>}, 100)
    assert_receive({:ok, worker, 2, <<2,2,2,2,2,2,2>>}, 100)
    assert_receive({:ok, worker, 3, <<3,3,3,3,3,3,3>>}, 100)
    assert_receive({:ok, worker, 4, <<4,4,4,4,4>>}, 100)
  end
end
