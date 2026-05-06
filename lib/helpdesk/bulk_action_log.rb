require "helpdesk/json_file"
require "helpdesk/log_entry"

module Helpdesk
  class BulkActionLog
    include JsonFileStore

    def initialize(path: default_path)
      configure_json_file(path, default: [])
    end

    def append(action:, rows:, metadata: {})
      entries = load_data
      entries << LogEntry.bulk_action(id: next_id(entries), action: action, rows: rows, metadata: metadata)
      save!(entries)
    end

    def pop_last
      entries = load_data
      entry = entries.pop
      save!(entries)
      entry
    end

    private

    def default_path
      File.expand_path("../../data/bulk_actions.json", __dir__)
    end
  end
end
