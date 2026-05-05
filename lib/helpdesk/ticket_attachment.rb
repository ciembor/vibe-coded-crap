require "time"

module Helpdesk
  class TicketAttachment
    def self.normalize_many(attachments, now: Time.now.utc)
      Array(attachments).each_with_index.map do |attachment, index|
        normalize(attachment, fallback_id: index + 1, now: now)
      end
    end

    def self.build(existing_attachments, name:, content_type: "", size: 0, description: "", uploaded_by: "agent", now: Time.now.utc)
      name = name.to_s.strip
      return nil if name.empty?

      {
        "id" => next_id(existing_attachments),
        "name" => name,
        "content_type" => content_type.to_s.strip,
        "size" => size.to_i,
        "description" => description.to_s.strip,
        "uploaded_by" => uploaded_by.to_s.strip.empty? ? "agent" : uploaded_by.to_s.strip,
        "created_at" => now.utc.iso8601
      }
    end

    def self.next_id(attachments)
      (Array(attachments).map { |attachment| attachment["id"].to_i }.max || 0) + 1
    end

    def self.normalize(attachment, fallback_id:, now:)
      attachment = attachment.is_a?(Hash) ? attachment : {}
      {
        "id" => attachment["id"] || attachment[:id] || fallback_id,
        "name" => attachment["name"] || attachment[:name],
        "content_type" => attachment["content_type"] || attachment[:content_type] || "",
        "size" => (attachment["size"] || attachment[:size] || 0).to_i,
        "description" => attachment["description"] || attachment[:description] || "",
        "uploaded_by" => attachment["uploaded_by"] || attachment[:uploaded_by] || "agent",
        "created_at" => attachment["created_at"] || attachment[:created_at] || now.utc.iso8601
      }
    end

    private_class_method :normalize
  end
end
