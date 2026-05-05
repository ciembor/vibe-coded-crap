require "json"
require "fileutils"
require "time"

module Helpdesk
  class AuditLog
    attr_reader :path

    def initialize(path: default_path)
      @path = path
      FileUtils.mkdir_p(File.dirname(path))
      save!([]) unless File.exist?(path)
    end

    def append(action:, actor:, subject:, details: {})
      entries = load_data
      entries << {
        "id" => next_id(entries),
        "action" => action,
        "actor" => actor,
        "subject" => subject,
        "details" => details,
        "created_at" => Time.now.utc.iso8601
      }
      save!(entries)
    end

    def all
      load_data
    end

    private

    def default_path
      File.expand_path("../../data/audit_log.json", __dir__)
    end

    def load_data
      JSON.parse(File.read(path))
    rescue Errno::ENOENT, JSON::ParserError
      []
    end

    def save!(rows)
      File.write(path, JSON.pretty_generate(rows))
    end

    def next_id(rows)
      (rows.map { |row| row["id"].to_i }.max || 0) + 1
    end
  end
end
