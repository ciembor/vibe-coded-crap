require "time"

module Helpdesk
  class TicketEntry
    def self.normalize_many(entries, now: Time.now.utc)
      Array(entries).map { |entry| normalize(entry, now: now) }
    end

    def self.build(existing_entries, body:, author: "agent", now: Time.now.utc)
      {
        "id" => next_id(existing_entries),
        "body" => body,
        "author" => author,
        "created_at" => now.utc.iso8601
      }
    end

    def self.next_id(entries)
      (Array(entries).map { |entry| entry["id"].to_i }.max || 0) + 1
    end

    def self.normalize(entry, now:)
      entry = entry.is_a?(Hash) ? entry : {}
      {
        "id" => entry["id"] || entry[:id],
        "body" => entry["body"] || entry[:body],
        "author" => entry["author"] || entry[:author] || "agent",
        "created_at" => entry["created_at"] || entry[:created_at] || now.utc.iso8601
      }
    end
    private_class_method :normalize
  end
end
