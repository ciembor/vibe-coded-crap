require "time"
require "helpdesk/json_file"

module Helpdesk
  class AuditLog
    include JsonFileStore

    def initialize(path: default_path)
      configure_json_file(path, default: [])
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
  end
end
