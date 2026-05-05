require "json"
require "fileutils"

module Helpdesk
  class JsonFile
    attr_reader :path

    def initialize(path, default:)
      @path = path
      @default_payload = copy_payload(default)
      FileUtils.mkdir_p(File.dirname(path))
      write(default) unless File.exist?(path)
    end

    def read
      parsed = JSON.parse(File.read(path))
      parsed.nil? ? copy_payload(@default_payload) : parsed
    rescue Errno::ENOENT, JSON::ParserError
      copy_payload(@default_payload)
    end

    def write(payload)
      FileUtils.mkdir_p(File.dirname(path))
      temporary_path = "#{path}.tmp-#{Process.pid}-#{object_id}"
      File.write(temporary_path, JSON.pretty_generate(payload))
      File.rename(temporary_path, path)
      payload
    ensure
      FileUtils.rm_f(temporary_path) if temporary_path && File.exist?(temporary_path)
    end

    def next_id(rows)
      (Array(rows).map { |row| row["id"].to_i }.max || 0) + 1
    end

    private

    def copy_payload(payload)
      Marshal.load(Marshal.dump(payload))
    rescue TypeError
      JSON.parse(JSON.generate(payload))
    end
  end

  module JsonFileStore
    attr_reader :path

    private

    def configure_json_file(path, default:)
      @json_file = JsonFile.new(path, default: default)
      @path = @json_file.path
    end

    def load_data
      @json_file.read
    end

    def save!(payload)
      @json_file.write(payload)
    end

    def next_id(rows)
      @json_file.next_id(rows)
    end
  end
end
