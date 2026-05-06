require "date"
require "json"
require "time"

module Helpdesk
  class TicketMerger
    def initialize(repository)
      @repository = repository
    end

    def merge(source_id, target_id)
      source_id = source_id.to_i
      target_id = target_id.to_i
      raise ArgumentError, "merge requires two ticket IDs" if source_id.zero? || target_id.zero?
      raise ArgumentError, "cannot merge a ticket into itself" if source_id == target_id

      @repository.transaction do |tickets|
        source = tickets.find(source_id)
        target = tickets.find(target_id)
        next nil unless source && target

        copy_entries(target, source, prefix: "Merged from")
        source.tags.each { |tag| target.add_tag(tag) }
        source.watchers.each { |watcher_id| target.add_watcher(watcher_id) }
        source.custom_fields.each do |key, value|
          target.custom_fields[key] = value if target.custom_fields[key].to_s.strip.empty?
        end

        target.update(merged_from_ids: target.merged_from_ids + [source.id])
        source.description = [source.description, "Merged into ticket ##{target.id}."].reject(&:empty?).join("\n\n")
        source.custom_fields = source.custom_fields.merge("merged_into" => target.id.to_s)
        source.update(merged_into_id: target.id, archived: true, status: "closed", custom_fields: source.custom_fields)

        @repository.validate!(target)
        @repository.validate!(source)
        { source: source, target: target }
      end
    end

    def import_json(path)
      rows = JSON.parse(File.read(path))
      raise ArgumentError, "import file must contain an array of tickets" unless rows.is_a?(Array)

      @repository.transaction do |tickets|
        imported = 0
        merged = 0
        remapped = 0

        rows.each do |row|
          imported_ticket = Ticket.from_h(row)
          existing = tickets.find(imported_ticket.id)
          duplicate = tickets.find { |ticket| ticket.duplicate_key == imported_ticket.duplicate_key }

          if duplicate
            merge_imported_ticket(duplicate, imported_ticket)
            @repository.validate!(duplicate)
            merged += 1
          elsif existing
            remapped_ticket = Ticket.from_h(imported_ticket.to_h)
            remapped_ticket.id = tickets.next_id
            remapped_ticket.normalize!
            @repository.validate!(remapped_ticket)
            tickets.add(remapped_ticket)
            remapped += 1
          else
            @repository.validate!(imported_ticket)
            tickets.add(imported_ticket)
          end

          imported += 1
        end

        { imported: imported, merged: merged, remapped: remapped }
      end
    rescue Errno::ENOENT
      raise ArgumentError, "import file not found: #{path}"
    rescue JSON::ParserError
      raise ArgumentError, "import file is not valid JSON: #{path}"
    end

    private

    def merge_imported_ticket(existing, source)
      existing.title = choose_nonempty(existing.title, source.title)
      existing.description = choose_nonempty(existing.description, source.description)
      existing.status = choose_status(existing.status, source.status)
      existing.priority = choose_priority(existing.priority, source.priority)
      existing.ticket_type = choose_nonempty(existing.ticket_type, source.ticket_type)
      existing.due_at = choose_due_at(existing.due_at, source.due_at)
      existing.reminder_at = choose_reminder_at(existing.reminder_at, source.reminder_at)
      existing.reminder_repeat = choose_nonempty(existing.reminder_repeat, source.reminder_repeat)
      existing.tags = (existing.tags + source.tags).uniq.sort
      existing.watchers = (existing.watchers + source.watchers).uniq.sort
      existing.pinned = existing.pinned? || source.pinned?
      existing.archived = existing.archived? || source.archived?
      existing.custom_fields = existing.custom_fields.merge(source.custom_fields) do |_key, left, right|
        left.to_s.strip.empty? ? right : left
      end

      copy_entries(existing, source, prefix: "Imported from")
      existing.normalize!
    end

    def copy_entries(target, source, prefix:)
      source.comments.each do |comment|
        target.add_comment(
          body: "[#{prefix} ##{source.id}] #{comment["body"]}",
          author: comment["author"]
        )
      end

      source.internal_notes.each do |note|
        target.add_internal_note(
          body: "[#{prefix} ##{source.id}] #{note["body"]}",
          author: note["author"]
        )
      end

      source.attachments.each do |attachment|
        target.add_attachment(
          name: "[#{prefix} ##{source.id}] #{attachment["name"]}",
          content_type: attachment["content_type"],
          size: attachment["size"],
          description: attachment["description"],
          uploaded_by: attachment["uploaded_by"]
        )
      end
    end

    def choose_nonempty(current, incoming)
      current.to_s.strip.empty? ? incoming : current
    end

    def choose_status(current, incoming)
      choose_by_order(current, incoming, %w[open in_progress waiting resolved closed])
    end

    def choose_priority(current, incoming)
      choose_by_order(current, incoming, %w[urgent high medium low])
    end

    def choose_by_order(current, incoming, order)
      current_index = order.index(current.to_s) || order.length
      incoming_index = order.index(incoming.to_s) || order.length
      incoming_index < current_index ? incoming : current
    end

    def choose_due_at(current, incoming)
      choose_earlier(current, incoming) { |value| Date.parse(value.to_s) }
    end

    def choose_reminder_at(current, incoming)
      choose_earlier(current, incoming) { |value| Time.parse(value.to_s).utc }
    end

    def choose_earlier(current, incoming)
      current_value = parse_ordered_value(current) { |value| yield value }
      incoming_value = parse_ordered_value(incoming) { |value| yield value }
      return incoming if current_value.nil? && incoming_value
      return current if incoming_value.nil? && current_value
      return current if current_value.nil? && incoming_value.nil?

      incoming_value < current_value ? incoming : current
    end

    def parse_ordered_value(value)
      return nil if value.to_s.strip.empty?

      yield value
    rescue ArgumentError
      nil
    end
  end
end
