module Helpdesk
  class TicketBulkActions
    def initialize(repository, relationships, bulk_action_log)
      @repository = repository
      @relationships = relationships
      @bulk_action_log = bulk_action_log
    end

    def bulk_close(ids, actor_role: nil)
      id_list = normalize_ids(ids)
      return [] if id_list.empty?

      @repository.transaction do |tickets|
        closed_ids = []
        affected_rows = []

        tickets.each do |ticket|
          next unless id_list.include?(ticket.id.to_i)
          next if ticket.deleted?
          next unless @relationships.closeable_ticket?(ticket, tickets: tickets)
          next unless ticket.can_transition_to?("closed", role: actor_role)

          affected_rows << ticket.to_h
          ticket.update(status: "closed")
          @repository.validate!(ticket)
          closed_ids << ticket.id
        end

        @bulk_action_log.append(action: "bulk_close", rows: affected_rows) unless affected_rows.empty?
        closed_ids
      end
    end

    def bulk_tag(ids, tag, action:)
      id_list = normalize_ids(ids)
      tag = tag.to_s.strip
      return [] if id_list.empty? || tag.empty?
      raise ArgumentError, "invalid bulk tag action: #{action}" unless %w[add remove].include?(action.to_s)

      @repository.transaction do |tickets|
        touched_ids = []
        affected_rows = []

        tickets.each do |ticket|
          next unless id_list.include?(ticket.id.to_i)
          next if ticket.deleted?

          affected_rows << ticket.to_h
          action.to_s == "add" ? ticket.add_tag(tag) : ticket.remove_tag(tag)
          @repository.validate!(ticket)
          touched_ids << ticket.id
        end

        metadata = { "tag" => tag }
        @bulk_action_log.append(action: "bulk_tag_#{action}", rows: affected_rows, metadata: metadata) unless affected_rows.empty?
        touched_ids
      end
    end

    def undo_last_bulk_action
      entry = @bulk_action_log.pop_last
      return nil unless entry

      rows = entry["rows"] || []
      return nil if rows.empty?

      @repository.restore_rows(rows)
      entry
    end

    private

    def normalize_ids(ids)
      Array(ids).map(&:to_i).reject(&:zero?).uniq
    end
  end
end
