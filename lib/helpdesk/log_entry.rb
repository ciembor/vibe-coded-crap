require "time"

module Helpdesk
  class LogEntry
    def self.audit(id:, action:, actor:, subject:, details: {}, now: Time.now.utc)
      {
        "id" => id,
        "action" => action,
        "actor" => actor,
        "subject" => subject,
        "details" => details,
        "created_at" => now.utc.iso8601
      }
    end

    def self.bulk_action(id:, action:, rows:, metadata: {}, now: Time.now.utc)
      {
        "id" => id,
        "action" => action,
        "rows" => rows,
        "metadata" => metadata,
        "created_at" => now.utc.iso8601
      }
    end
  end
end
