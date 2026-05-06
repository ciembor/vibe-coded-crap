require "helpdesk/json_file"
require "helpdesk/log_entry"

module Helpdesk
  class AuditLog
    include JsonFileStore

    def initialize(path: default_path)
      configure_json_file(path, default: [])
    end

    def append(action:, actor:, subject:, details: {})
      entries = load_data
      entries << LogEntry.audit(id: next_id(entries), action: action, actor: actor, subject: subject, details: details)
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
