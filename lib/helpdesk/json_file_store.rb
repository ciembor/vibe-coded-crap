require "json"
require "fileutils"

module Helpdesk
  class JsonFileStore
    attr_reader :path

    def initialize(path: default_path)
      @path = path
      FileUtils.mkdir_p(File.dirname(path))
      save!(default_payload) unless File.exist?(path)
    end

    protected

    def default_payload
      []
    end

    def load_data
      parsed = JSON.parse(File.read(path))
      normalize_loaded_payload(parsed)
    rescue Errno::ENOENT, JSON::ParserError
      default_payload
    end

    def save!(payload)
      File.write(path, JSON.pretty_generate(payload))
    end

    def next_id(rows)
      (Array(rows).map { |row| row["id"].to_i }.max || 0) + 1
    end

    def normalize_loaded_payload(payload)
      payload
    end
  end
end
