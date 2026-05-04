require "json"
require "fileutils"
require "helpdesk/bulk_action_log"
require "helpdesk/ticket"

module Helpdesk
  class Store
    attr_reader :path

    def initialize(path: default_path)
      @path = path
      @bulk_action_log = BulkActionLog.new
      FileUtils.mkdir_p(File.dirname(path))
      save!([]) unless File.exist?(path)
    end

    def all
      load_data.map { |row| Ticket.from_h(row) }
    end

    def duplicate_groups
      tickets = all.reject(&:archived?)
      tickets.group_by(&:duplicate_key).values.select { |group| group.count > 1 }
    end

    def duplicate_candidates_for(ticket, limit: 5)
      key = ticket.duplicate_key
      candidates = all.reject { |existing| existing.id.to_i == ticket.id.to_i }
      matches =
        candidates.select do |existing|
          existing.duplicate_key == key ||
            existing.duplicate_title_key == ticket.duplicate_title_key
        end
      matches.sort_by { |existing| [existing.status == "closed" ? 1 : 0, existing.updated_at.to_s] }.take(limit)
    end

    def related_tickets(ticket)
      all.select { |existing| ticket.related_ids.include?(existing.id.to_i) }
    end

    def parent_ticket(ticket)
      return nil if ticket.parent_id.nil?

      find(ticket.parent_id)
    end

    def child_tickets(ticket)
      all.select { |existing| ticket.child_ids.include?(existing.id.to_i) }
    end

    def relate(source_id, target_id)
      source_id = source_id.to_i
      target_id = target_id.to_i
      raise ArgumentError, "relate requires two ticket IDs" if source_id.zero? || target_id.zero?
      raise ArgumentError, "cannot relate a ticket to itself" if source_id == target_id

      tickets = load_data
      source_index = tickets.index { |row| row["id"].to_i == source_id }
      target_index = tickets.index { |row| row["id"].to_i == target_id }
      return nil unless source_index && target_index

      source = Ticket.from_h(tickets[source_index])
      target = Ticket.from_h(tickets[target_index])
      source.send(:relate_to, target.id)
      target.send(:relate_to, source.id)

      tickets[source_index] = source.to_h
      tickets[target_index] = target.to_h
      save!(tickets)
      { source: source, target: target }
    end

    def unrelate(source_id, target_id)
      source_id = source_id.to_i
      target_id = target_id.to_i
      raise ArgumentError, "unrelate requires two ticket IDs" if source_id.zero? || target_id.zero?
      raise ArgumentError, "cannot unrelate a ticket from itself" if source_id == target_id

      tickets = load_data
      source_index = tickets.index { |row| row["id"].to_i == source_id }
      target_index = tickets.index { |row| row["id"].to_i == target_id }
      return nil unless source_index && target_index

      source = Ticket.from_h(tickets[source_index])
      target = Ticket.from_h(tickets[target_index])
      source.send(:unrelate, target.id)
      target.send(:unrelate, source.id)

      tickets[source_index] = source.to_h
      tickets[target_index] = target.to_h
      save!(tickets)
      { source: source, target: target }
    end

    def set_parent(child_id, parent_id)
      child_id = child_id.to_i
      parent_id = parent_id.to_i
      raise ArgumentError, "set_parent requires two ticket IDs" if child_id.zero? || parent_id.zero?
      raise ArgumentError, "cannot set a ticket as its own parent" if child_id == parent_id

      tickets = load_data
      child_index = tickets.index { |row| row["id"].to_i == child_id }
      parent_index = tickets.index { |row| row["id"].to_i == parent_id }
      return nil unless child_index && parent_index

      child = Ticket.from_h(tickets[child_index])
      parent = Ticket.from_h(tickets[parent_index])
      old_parent = child.parent_id ? tickets.find { |row| row["id"].to_i == child.parent_id.to_i } : nil
      child.send(:set_parent, parent.id)
      parent.send(:add_child, child.id)

      tickets[child_index] = child.to_h
      tickets[parent_index] = parent.to_h
      if old_parent && old_parent["id"].to_i != parent.id.to_i
        old_parent_ticket = Ticket.from_h(old_parent)
        old_parent_ticket.send(:remove_child, child.id)
        old_parent_index = tickets.index { |row| row["id"].to_i == old_parent_ticket.id.to_i }
        tickets[old_parent_index] = old_parent_ticket.to_h if old_parent_index
      end
      save!(tickets)
      { child: child, parent: parent }
    end

    def clear_parent(child_id)
      child_id = child_id.to_i
      raise ArgumentError, "clear_parent requires a ticket ID" if child_id.zero?

      tickets = load_data
      child_index = tickets.index { |row| row["id"].to_i == child_id }
      return nil unless child_index

      child = Ticket.from_h(tickets[child_index])
      parent = child.parent_id ? find(child.parent_id) : nil
      child.send(:clear_parent)
      tickets[child_index] = child.to_h
      if parent
        parent_index = tickets.index { |row| row["id"].to_i == parent.id.to_i }
        if parent_index
          parent = Ticket.from_h(tickets[parent_index])
          parent.send(:remove_child, child.id)
          tickets[parent_index] = parent.to_h
        end
      end
      save!(tickets)
      { child: child, parent: parent }
    end

    def find(id)
      all.find { |ticket| ticket.id.to_i == id.to_i }
    end

    def create(attrs)
      tickets = load_data
      ticket = Ticket.new(
        id: next_id(tickets),
        title: attrs.fetch(:title),
        description: attrs.fetch(:description, ""),
        status: attrs.fetch(:status, "open"),
        priority: attrs.fetch(:priority, "medium"),
        tags: attrs.fetch(:tags, []),
        internal_notes: attrs.fetch(:internal_notes, []),
        attachments: attrs.fetch(:attachments, []),
        custom_fields: attrs.fetch(:custom_fields, {}),
        ticket_type: attrs.fetch(:ticket_type, "general"),
        due_at: attrs.fetch(:due_at, nil),
        reminder_at: attrs.fetch(:reminder_at, nil),
        reminder_repeat: attrs.fetch(:reminder_repeat, nil)
      ).normalize!
      validate_ticket!(ticket)
      tickets << ticket.to_h
      save!(tickets)
      ticket
    end

    def update(id, attrs)
      tickets = load_data
      index = tickets.index { |row| row["id"].to_i == id.to_i }
      return nil unless index

      ticket = Ticket.from_h(tickets[index]).update(attrs)
      validate_ticket!(ticket)
      tickets[index] = ticket.to_h
      save!(tickets)
      ticket
    end

    def delete(id)
      tickets = load_data
      removed = tickets.reject! { |row| row["id"].to_i == id.to_i }
      save!(tickets) if removed
      !removed.nil?
    end

    def bulk_close(ids)
      id_list = Array(ids).map(&:to_i).uniq
      return [] if id_list.empty?

      tickets = load_data
      closed_ids = []
      affected_rows = []

      tickets.each do |row|
        next unless id_list.include?(row["id"].to_i)

        affected_rows << row.dup
        ticket = Ticket.from_h(row)
        ticket.update(status: "closed")
        row.replace(ticket.to_h)
        closed_ids << ticket.id
      end

      save!(tickets)
      @bulk_action_log.append(action: "bulk_close", rows: affected_rows) unless affected_rows.empty?
      closed_ids
    end

    def bulk_tag(ids, tag, action:)
      id_list = Array(ids).map(&:to_i).uniq
      tag = tag.to_s.strip
      return [] if id_list.empty? || tag.empty?

      tickets = load_data
      touched_ids = []
      affected_rows = []

      tickets.each do |row|
        next unless id_list.include?(row["id"].to_i)

        affected_rows << row.dup
        ticket = Ticket.from_h(row)
        case action
        when "add"
          ticket.add_tag(tag)
        when "remove"
          ticket.remove_tag(tag)
        else
          raise ArgumentError, "invalid bulk tag action: #{action}"
        end
        row.replace(ticket.to_h)
        touched_ids << ticket.id
      end

      save!(tickets)
      @bulk_action_log.append(action: "bulk_tag_#{action}", rows: affected_rows, metadata: { "tag" => tag }) unless affected_rows.empty?
      touched_ids
    end

    def save_ticket(ticket)
      validate_ticket!(ticket)
      tickets = load_data
      index = tickets.index { |row| row["id"].to_i == ticket.id.to_i }
      if index
        tickets[index] = ticket.to_h
      else
        tickets << ticket.to_h
      end
      save!(tickets)
      ticket
    end

    def merge(source_id, target_id)
      source_id = source_id.to_i
      target_id = target_id.to_i
      raise ArgumentError, "merge requires two ticket IDs" if source_id.zero? || target_id.zero?
      raise ArgumentError, "cannot merge a ticket into itself" if source_id == target_id

      tickets = load_data
      source_index = tickets.index { |row| row["id"].to_i == source_id }
      target_index = tickets.index { |row| row["id"].to_i == target_id }
      return nil unless source_index && target_index

      source = Ticket.from_h(tickets[source_index])
      target = Ticket.from_h(tickets[target_index])

      source.comments.each do |comment|
        target.add_comment(
          body: "[Merged from ##{source.id}] #{comment["body"]}",
          author: comment["author"]
        )
      end

      source.internal_notes.each do |note|
        target.add_internal_note(
          body: "[Merged from ##{source.id}] #{note["body"]}",
          author: note["author"]
        )
      end

      source.attachments.each do |attachment|
        target.add_attachment(
          name: "[Merged from ##{source.id}] #{attachment["name"]}",
          content_type: attachment["content_type"],
          size: attachment["size"],
          description: attachment["description"],
          uploaded_by: attachment["uploaded_by"]
        )
      end

      source.tags.each { |tag| target.add_tag(tag) }
      source.watchers.each { |watcher_id| target.add_watcher(watcher_id) }

      source.custom_fields.each do |key, value|
        target.custom_fields[key] = value if target.custom_fields[key].to_s.strip.empty?
      end

      target.send(:add_merged_from, source.id)
      source.send(:merge_into!, target.id)
      source.description = [source.description, "Merged into ticket ##{target.id}."].reject(&:empty?).join("\n\n")
      source.custom_fields = source.custom_fields.merge("merged_into" => target.id.to_s)

      tickets[target_index] = target.to_h
      tickets[source_index] = source.to_h
      save!(tickets)
      { source: source, target: target }
    end

    def undo_last_bulk_action
      entry = @bulk_action_log.pop_last
      return nil unless entry

      rows = entry["rows"] || []
      return nil if rows.empty?

      tickets = load_data
      rows.each do |row|
        index = tickets.index { |existing| existing["id"].to_i == row["id"].to_i }
        if index
          tickets[index] = row
        else
          tickets << row
        end
      end
      save!(tickets)
      entry
    end

    def import_json(path)
      rows = JSON.parse(File.read(path))
      unless rows.is_a?(Array)
        raise ArgumentError, "import file must contain an array of tickets"
      end

      tickets = load_data
      imported = 0
      merged = 0
      remapped = 0

      rows.each do |row|
        imported_ticket = Ticket.from_h(row)
        existing_index = tickets.index { |existing| existing["id"].to_i == imported_ticket.id.to_i }
        duplicate_index = tickets.index do |existing|
          existing_ticket = Ticket.from_h(existing)
          existing_ticket.duplicate_key == imported_ticket.duplicate_key
        end

        if duplicate_index
          merged_ticket = merge_imported_ticket(Ticket.from_h(tickets[duplicate_index]), imported_ticket)
          tickets[duplicate_index] = merged_ticket.to_h
          merged += 1
        elsif existing_index
          remapped_ticket = Ticket.from_h(imported_ticket.to_h)
          remapped_ticket.id = next_id(tickets)
          remapped_ticket.normalize!
          tickets << remapped_ticket.to_h
          remapped += 1
        else
          tickets << imported_ticket.to_h
        end

        imported += 1
      end

      save!(tickets)
      {
        imported: imported,
        merged: merged,
        remapped: remapped
      }
    rescue Errno::ENOENT
      raise ArgumentError, "import file not found: #{path}"
    rescue JSON::ParserError
      raise ArgumentError, "import file is not valid JSON: #{path}"
    end

    private

    def default_path
      File.expand_path("../../data/tickets.json", __dir__)
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

    def validate_ticket!(ticket)
      errors = ticket.validation_errors
      return if errors.empty?

      raise ArgumentError, errors.join("; ")
    end

    def merge_imported_ticket(existing_ticket, imported_ticket)
      existing = Ticket.from_h(existing_ticket.to_h)
      source = imported_ticket

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

      source.comments.each do |comment|
        existing.add_comment(
          body: "[Imported from ##{source.id}] #{comment["body"]}",
          author: comment["author"]
        )
      end

      source.internal_notes.each do |note|
        existing.add_internal_note(
          body: "[Imported from ##{source.id}] #{note["body"]}",
          author: note["author"]
        )
      end

      source.attachments.each do |attachment|
        existing.add_attachment(
          name: "[Imported from ##{source.id}] #{attachment["name"]}",
          content_type: attachment["content_type"],
          size: attachment["size"],
          description: attachment["description"],
          uploaded_by: attachment["uploaded_by"]
        )
      end

      existing.normalize!
    end

    def choose_nonempty(current, incoming)
      current.to_s.strip.empty? ? incoming : current
    end

    def choose_status(current, incoming)
      order = %w[open in_progress waiting resolved closed]
      current_index = order.index(current.to_s) || order.length
      incoming_index = order.index(incoming.to_s) || order.length
      incoming_index < current_index ? incoming : current
    end

    def choose_priority(current, incoming)
      order = %w[urgent high medium low]
      current_index = order.index(current.to_s) || order.length
      incoming_index = order.index(incoming.to_s) || order.length
      incoming_index < current_index ? incoming : current
    end

    def choose_due_at(current, incoming)
      current_date = parse_date(current)
      incoming_date = parse_date(incoming)
      return incoming if current_date.nil? && incoming_date
      return current if incoming_date.nil? && current_date
      return current if current_date.nil? && incoming_date.nil?

      incoming_date < current_date ? incoming : current
    end

    def choose_reminder_at(current, incoming)
      current_time = parse_time(current)
      incoming_time = parse_time(incoming)
      return incoming if current_time.nil? && incoming_time
      return current if incoming_time.nil? && current_time
      return current if current_time.nil? && incoming_time.nil?

      incoming_time < current_time ? incoming : current
    end

    def parse_date(value)
      return nil if value.to_s.strip.empty?

      Date.parse(value.to_s)
    rescue ArgumentError
      nil
    end

    def parse_time(value)
      return nil if value.to_s.strip.empty?

      Time.parse(value.to_s).utc
    rescue ArgumentError
      nil
    end
  end
end
