defmodule Core.Test.Bencoding do
  use ExUnit.Case

  alias Core.Bencoding, as: Bencoding


  test "integer decoding and encoding" do
    pairs = [
      {"i0e", 0},
      {"i10e", 10},
      {"i-10e", -10},
      {"i999999e", 999999}
    ]

    Enum.each(pairs, fn {input, expected_output} ->
      {:ok, output} = Bencoding.decode(input)
      assert output == expected_output
    end)

    Enum.each(pairs, fn {expected_output, input} ->
      {:ok, output} = Bencoding.encode(input)
      assert output == expected_output
    end)
  end

  test "string decoding and encoding" do
    pairs = [
      {"0:", ""},
      {"4:test", "test"},
      {"5:" <> <<1,2,3,4,5>>, <<1,2,3,4,5>>},
    ]

    Enum.each(pairs, fn {input, expected_output} ->
      {:ok, output} = Bencoding.decode(input)
      assert output == expected_output
    end)

    Enum.each(pairs, fn {expected_output, input} ->
      {:ok, output} = Bencoding.encode(input)
      assert output == expected_output
    end)
  end

  test "list decoding and encoding" do
    pairs = [
      {"le", []},
      {"li1ei2e4:spam4:eggse", [1, 2, "spam", "eggs"]},
      {"llli1eeei2ee", [[[1]], 2]},
    ]

    Enum.each(pairs, fn {input, expected_output} ->
      {:ok, output} = Bencoding.decode(input)
      assert output == expected_output
    end)

    Enum.each(pairs, fn {expected_output, input} ->
      {:ok, output} = Bencoding.encode(input)
      assert output == expected_output
    end)
  end

  test "map decoding" do
    pairs = [
      {"de", %{}},
      {"d4:spam4:eggs3:fooli1eee", %{"spam" => "eggs", "foo" => [1]}},
      {"d3:food3:bardeee", %{"foo" => %{"bar" => %{}}}},
    ]

    Enum.each(pairs, fn {input, expected_output} ->
      {:ok, output} = Bencoding.decode(input)
      assert output == expected_output
    end)
  end

  test "nested decoding" do
    pairs = [
      {
        "d3:food3:barli1e4:testd4:spamleeee4:eggsd5:eggs2li1eeee",
        %{
          "foo" => %{"bar" => [1, "test", %{"spam" => []}]},
          "eggs" => %{"eggs2" => [1]}}
        }
    ]

    Enum.each(pairs, fn {input, expected_output} ->
      {:ok, output} = Bencoding.decode(input)
      assert output == expected_output
    end)
  end

  test "map encoding" do
    pairs = [
      {%{}, "de"},
      {%{"spam" => "eggs"}, "d4:spam4:eggse"},
      {%{"foo" => %{"bar" => %{"spam" => [1, 2, %{}]}}}, "d3:food3:bard4:spamli1ei2edeeeee"}
    ]

    Enum.each(pairs, fn {input, expected_output} ->
      {:ok, output} = Bencoding.encode(input)
      assert output == expected_output
    end)
  end
end
