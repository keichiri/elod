defmodule Core.Test.Metafile do
  use ExUnit.Case

  alias Core.Metafile, as: Metafile
  alias Core.File, as: File
  alias Core.Piece, as: Piece


  test "metafile parsing" do
    url = "www.test-url.com"
    encoded_url = "8:announce#{byte_size(url)}:#{url}"
    encoded_pieces = "6:pieces40:1111111111111111111122222222222222222222"
    encoded_piece_length = "12:piece lengthi20e"
    encoded_file_name = "4:name4:base"
    encoded_file_1 = "d4:pathl4:dir15:1.txte6:lengthi22ee"
    encoded_file_2 = "d4:pathl4:dir25:2.txte6:lengthi15ee"
    encoded_files = "5:filesl#{encoded_file_1}#{encoded_file_2}e"
    encoded_info = "d#{encoded_pieces}#{encoded_piece_length}#{encoded_file_name}#{encoded_files}e"
    metafile_content = "d#{encoded_url}4:info#{encoded_info}e"
    expected_info_hash = :crypto.hash(:sha, encoded_info)
    expected_pieces = [
      %Piece{
        index: 0,
        length: 20,
        hash: "11111111111111111111",
        data: nil
      },
      %Piece{
        index: 1,
        length: 17,
        hash: "22222222222222222222",
        data: nil
      }
    ]
    expected_files = [
      %File{
        length: 22,
        path: "base/dir1/1.txt"
      },
      %File{
        length: 15,
        path: "base/dir2/2.txt"
      }
    ]

    {:ok, metafile} = Metafile.parse_from_binary(metafile_content)

    assert metafile.announce_url == url
    assert metafile.info_hash == expected_info_hash
    assert metafile.pieces == expected_pieces
    assert metafile.files == expected_files
  end
end
