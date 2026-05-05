require "test_helper"

class JsonFileTest < Minitest::Test
  def test_reads_default_payload_for_missing_or_invalid_json_and_allocates_ids
    with_tmpdir do |dir|
      path = File.join(dir, "records.json")
      file = Helpdesk::JsonFile.new(path, default: [])

      assert_equal [], file.read

      File.write(path, "{invalid")
      assert_equal [], file.read

      file.write([{ "id" => 7, "name" => "existing" }])
      assert_equal 8, file.next_id(file.read)
    end
  end
end
