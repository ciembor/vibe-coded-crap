require "time"
require "helpdesk/json_file_store"

module Helpdesk
  class BulkActionLog < JsonFileStore

    def append(action:, rows:, metadata: {})
      entries = load_data
      entries << {
        "id" => next_id(entries),
        "action" => action,
        "rows" => rows,
        "metadata" => metadata,
        "created_at" => Time.now.utc.iso8601
      }
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
