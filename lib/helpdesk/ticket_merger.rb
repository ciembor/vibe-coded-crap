require "helpdesk/ticket"

module Helpdesk
  class TicketMerger
    def initialize(rows)
      @rows = rows
    end

    def merge(source_id, target_id)
      source_id = source_id.to_i
      target_id = target_id.to_i
      raise ArgumentError, "merge requires two ticket IDs" if source_id.zero? || target_id.zero?
      raise ArgumentError, "cannot merge a ticket into itself" if source_id == target_id

      source_index = index_for(source_id)
      target_index = index_for(target_id)
      return nil unless source_index && target_index

      source = ticket_at(source_index)
      target = ticket_at(target_index)
      copy_activity(source, target, label: "Merged from")
      source.tags.each { |tag| target.add_tag(tag) }
      source.watchers.each { |watcher_id| target.add_watcher(watcher_id) }
      merge_custom_fields(source, target)

      target.add_merged_from(source.id)
      source.merge_into!(target.id)
      source.description = [source.description, "Merged into ticket ##{target.id}."].reject(&:empty?).join("\n\n")
      source.custom_fields = source.custom_fields.merge("merged_into" => target.id.to_s)

      replace(target_index, target)
      replace(source_index, source)
      { source: source, target: target }
    end

    def self.copy_activity(source, target, label:)
      new([]).copy_activity(source, target, label: label)
    end

    def copy_activity(source, target, label:)
      source.comments.each do |comment|
        target.add_comment(
          body: "[#{label} ##{source.id}] #{comment["body"]}",
          author: comment["author"]
        )
      end

      source.internal_notes.each do |note|
        target.add_internal_note(
          body: "[#{label} ##{source.id}] #{note["body"]}",
          author: note["author"]
        )
      end

      source.attachments.each do |attachment|
        target.add_attachment(
          name: "[#{label} ##{source.id}] #{attachment["name"]}",
          content_type: attachment["content_type"],
          size: attachment["size"],
          description: attachment["description"],
          uploaded_by: attachment["uploaded_by"]
        )
      end
    end

    private

    def index_for(id)
      @rows.index { |row| row["id"].to_i == id.to_i }
    end

    def ticket_at(index)
      Ticket.from_h(@rows[index])
    end

    def replace(index, ticket)
      @rows[index] = ticket.to_h
    end

    def merge_custom_fields(source, target)
      source.custom_fields.each do |key, value|
        target.custom_fields[key] = value if target.custom_fields[key].to_s.strip.empty?
      end
    end
  end
end
