require "csv"
require "json"
require "fileutils"

module Helpdesk
  class TicketExporter
    CSV_HEADER = %w[
      id title description status priority due_at overdue reminder_at reminder_repeat
      tags comment_count created_at updated_at closed_at
    ].freeze

    def initialize(tickets)
      @tickets = tickets
    end

    def export_csv(path)
      ensure_directory(path)
      CSV.open(path, "w") do |csv|
        csv << CSV_HEADER
        @tickets.each { |ticket| csv << csv_row(ticket) }
      end
      @tickets.count
    end

    def export_json(path)
      ensure_directory(path)
      File.write(path, JSON.pretty_generate(@tickets.map(&:to_h)))
      @tickets.count
    end

    private

    def ensure_directory(path)
      FileUtils.mkdir_p(File.dirname(path))
    end

    def csv_row(ticket)
      [
        ticket.id,
        ticket.title,
        ticket.description,
        ticket.status,
        ticket.priority,
        ticket.due_at,
        ticket.overdue?,
        ticket.reminder_at,
        ticket.reminder_repeat,
        ticket.tags.join(";"),
        ticket.comments.count,
        ticket.created_at,
        ticket.updated_at,
        ticket.closed_at
      ]
    end
  end
end
