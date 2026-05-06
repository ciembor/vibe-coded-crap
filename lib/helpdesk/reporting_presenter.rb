require "date"
require "time"
require "helpdesk/ticket_presenter"

module Helpdesk
  class ReportingPresenter
    def self.dashboard(tickets, duplicate_groups:)
      counts = tickets.group_by(&:status).transform_values(&:count)
      priority_counts = tickets.group_by(&:priority).transform_values(&:count)
      recent_tickets = tickets.sort_by { |ticket| ticket.updated_at.to_s }.reverse.take(5)
      open_tickets = open_ticket_scope(tickets)
      oldest_open_ticket = open_tickets.min_by { |ticket| ticket.created_at.to_s }
      lines = [
        "Dashboard",
        "Total tickets: #{tickets.count}",
        "Open: #{counts.fetch("open", 0)}",
        "In progress: #{counts.fetch("in_progress", 0)}",
        "Waiting: #{counts.fetch("waiting", 0)}",
        "Resolved: #{counts.fetch("resolved", 0)}",
        "Closed: #{counts.fetch("closed", 0)}",
        "Overdue: #{tickets.count(&:overdue?)}",
        "Due reminders: #{tickets.count(&:reminder_due?)}",
        "Escalations needed: #{tickets.count(&:escalation_needed?)}",
        "Duplicate groups: #{duplicate_groups.count}",
        "SLA warnings: #{tickets.count { |ticket| ticket.sla_status == "warning" }}",
        "SLA breaches: #{tickets.count { |ticket| ticket.sla_status == "breached" }}",
        "Total comments: #{tickets.sum { |ticket| ticket.comments.count }}",
        "Priority breakdown:"
      ]
      Ticket::PRIORITIES.each do |priority|
        lines << "  #{priority}: #{priority_counts.fetch(priority, 0)}"
      end
      lines << "Recent updates:"
      if recent_tickets.empty?
        lines << "  none"
      else
        recent_tickets.each do |ticket|
          lines << "  ##{ticket.id} #{ticket.title} (updated #{ticket.updated_at})"
        end
      end
      lines << if oldest_open_ticket
                 "Oldest open ticket: ##{oldest_open_ticket.id} #{oldest_open_ticket.title} (created #{oldest_open_ticket.created_at})"
               else
                 "Oldest open ticket: none"
               end
      lines.concat(top_tag_lines(tickets))
      lines.join("\n")
    end

    def self.analytics_summary(tickets)
      open_tickets = open_ticket_scope(tickets)
      closed_tickets = tickets.select(&:closed?)
      [
        "Analytics",
        "Total tickets: #{tickets.count}",
        "Open tickets: #{open_tickets.count}",
        "Closed tickets: #{closed_tickets.count}",
        "Overdue tickets: #{tickets.count(&:overdue?)}",
        "Escalation candidates: #{tickets.count(&:escalation_needed?)}",
        "SLA breaches: #{tickets.count { |ticket| ticket.sla_status == 'breached' }}",
        "Average open age (days): #{format_average_days(open_tickets, :created_at)}",
        "Average time to close (days): #{format_average_days(closed_tickets, :closed_at)}",
        "Total comments: #{tickets.sum { |ticket| ticket.comments.count }}"
      ].join("\n")
    end

    def self.analytics_status(tickets)
      counts = tickets.group_by(&:status).transform_values(&:count)
      total = tickets.count
      lines = ["Status analytics"]
      Ticket::STATUSES.each do |status|
        count = counts.fetch(status, 0)
        percentage = total.zero? ? 0 : ((count.to_f / total) * 100).round(1)
        lines << "#{status}: #{count} (#{percentage}%)"
      end
      lines << "Archived: #{tickets.count(&:archived?)}"
      lines << "Pinned: #{tickets.count(&:pinned?)}"
      lines.join("\n")
    end

    def self.analytics_aging(tickets)
      tickets = open_ticket_scope(tickets)
      return "No open tickets." if tickets.empty?

      buckets = {
        "0-2 days" => 0,
        "3-7 days" => 0,
        "8-14 days" => 0,
        "15+ days" => 0
      }
      tickets.each do |ticket|
        age = ticket_age_days(ticket)
        next if age.nil?

        case age
        when 0..2 then buckets["0-2 days"] += 1
        when 3..7 then buckets["3-7 days"] += 1
        when 8..14 then buckets["8-14 days"] += 1
        else buckets["15+ days"] += 1
        end
      end

      oldest_ticket = tickets.max_by { |ticket| ticket_age_days(ticket) || -1 }
      lines = [
        "Aging analytics",
        "Average open age (days): #{format_average_days(tickets, :created_at)}",
        "Oldest open ticket: ##{oldest_ticket.id} #{oldest_ticket.title}",
        "Aging buckets:"
      ]
      buckets.each do |label, count|
        lines << "  #{label}: #{count}"
      end
      lines.join("\n")
    end

    def self.analytics_trend(tickets, today: Date.today, days: 7)
      lines = ["Trend analytics"]
      days.downto(1) do |offset|
        date = today - offset
        created = tickets.count { |ticket| parse_date(ticket.created_at) == date }
        closed = tickets.count { |ticket| parse_date(ticket.closed_at) == date }
        lines << "#{date}: created #{created}, closed #{closed}"
      end
      lines.join("\n")
    end

    def self.daily_report(tickets, date)
      lines = ["Daily summary report for #{date}"]
      lines.concat(summary_metric_lines(tickets, date, date))
      lines.concat(priority_breakdown_lines(tickets))
      lines.concat(top_tag_lines(tickets))
      lines.join("\n")
    end

    def self.weekly_report(tickets, week_start, week_end)
      lines = ["Weekly summary report for #{week_start} to #{week_end}"]
      lines.concat(summary_metric_lines(tickets, week_start, week_end))
      lines.concat(priority_breakdown_lines(tickets))
      lines.concat(top_tag_lines(tickets))
      lines << "Daily breakdown:"
      (week_start..week_end).each do |date|
        day_stats = summary_metrics_for(tickets, date, date)
        lines << "  #{date}: created #{day_stats[:created]}, closed #{day_stats[:closed]}, updated #{day_stats[:updated]}"
      end
      lines.join("\n")
    end

    def self.duplicate_candidates(ticket, candidates)
      if candidates.empty?
        return "No duplicate candidates for ticket ##{ticket.id}."
      end

      lines = ["Duplicate candidates for ticket ##{ticket.id}:"]
      candidates.each { |candidate| lines << "  #{TicketPresenter.row(candidate)}" }
      lines.join("\n")
    end

    def self.duplicate_groups(groups)
      return "No duplicate tickets found." if groups.empty?

      lines = []
      groups.each_with_index do |group, index|
        lines << "Group #{index + 1}:"
        group.each { |ticket| lines << "  #{TicketPresenter.row(ticket)}" }
      end
      lines.join("\n")
    end

    def self.duplicate_candidate_warning(ticket, candidates)
      return nil if candidates.empty?

      lines = ["Warning: possible duplicates found for ticket ##{ticket.id}:"]
      candidates.each { |candidate| lines << "  #{TicketPresenter.row(candidate)}" }
      lines.join("\n")
    end

    def self.duplicate_group_warning(groups)
      return nil if groups.empty?

      lines = ["Duplicate ticket groups detected:"]
      groups.each_with_index do |group, index|
        lines << "  Group #{index + 1}:"
        group.each { |ticket| lines << "    #{TicketPresenter.row(ticket)}" }
      end
      lines.join("\n")
    end

    def self.summary_metrics_for(tickets, start_date, end_date)
      range = start_date..end_date
      {
        created: tickets.count { |ticket| date_in_range?(parse_date(ticket.created_at), range) },
        closed: tickets.count { |ticket| date_in_range?(parse_date(ticket.closed_at), range) },
        updated: tickets.count { |ticket| date_in_range?(parse_date(ticket.updated_at), range) },
        due: tickets.count { |ticket| date_in_range?(parse_date(ticket.due_at), range) },
        reminders: tickets.count { |ticket| date_in_range?(parse_time(ticket.reminder_at)&.to_date, range) },
        escalations: tickets.count { |ticket| ticket.escalation_needed? && date_in_range?(parse_date(ticket.created_at), range) },
        breaches: tickets.count { |ticket| ticket.sla_status == "breached" && date_in_range?(parse_date(ticket.created_at), range) }
      }
    end

    def self.summary_metric_lines(tickets, start_date, end_date)
      stats = summary_metrics_for(tickets, start_date, end_date)
      open_tickets = open_ticket_scope(tickets)
      [
        "Created: #{stats[:created]}",
        "Closed: #{stats[:closed]}",
        "Updated: #{stats[:updated]}",
        "Open now: #{open_tickets.count}",
        "Overdue now: #{tickets.count(&:overdue?)}",
        "Due in range: #{stats[:due]}",
        "Reminders due in range: #{stats[:reminders]}",
        "Escalation candidates in range: #{stats[:escalations]}",
        "SLA breaches in range: #{stats[:breaches]}"
      ]
    end
    private_class_method :summary_metric_lines

    def self.priority_breakdown_lines(tickets)
      lines = ["Top priorities:"]
      Ticket::PRIORITIES.each do |priority|
        lines << "  #{priority}: #{tickets.count { |ticket| ticket.priority == priority }}"
      end
      lines
    end
    private_class_method :priority_breakdown_lines

    def self.top_tag_lines(tickets)
      lines = ["Top tags:"]
      tag_counts = tickets.flat_map(&:tags).each_with_object(Hash.new(0)) { |tag, counts| counts[tag] += 1 }.sort_by { |tag, count| [-count, tag] }.first(5)
      if tag_counts.empty?
        lines << "  none"
      else
        tag_counts.each do |tag, count|
          lines << "  #{tag}: #{count}"
        end
      end
      lines
    end
    private_class_method :top_tag_lines

    def self.open_ticket_scope(tickets)
      tickets.select { |ticket| %w[open in_progress waiting].include?(ticket.status) }
    end
    private_class_method :open_ticket_scope

    def self.format_average_days(tickets, field)
      values =
        case field
        when :created_at
          tickets.map { |ticket| ticket_age_days(ticket) }.compact
        when :closed_at
          tickets.map { |ticket| ticket_close_duration_days(ticket) }.compact
        else
          []
        end

      return "n/a" if values.empty?

      (values.sum.to_f / values.count).round(1)
    end
    private_class_method :format_average_days

    def self.ticket_age_days(ticket, reference_date = Date.today)
      date = parse_date(ticket.created_at)
      return nil unless date

      (reference_date - date).to_i
    end
    private_class_method :ticket_age_days

    def self.ticket_close_duration_days(ticket)
      created = parse_date(ticket.created_at)
      closed = parse_date(ticket.closed_at)
      return nil unless created && closed

      (closed - created).to_i
    end
    private_class_method :ticket_close_duration_days

    def self.parse_date(value)
      return nil if value.to_s.strip.empty?

      Date.parse(value.to_s)
    rescue ArgumentError
      nil
    end
    private_class_method :parse_date

    def self.date_in_range?(date, range)
      date && range.cover?(date)
    end
    private_class_method :date_in_range?

    def self.parse_time(value)
      return nil if value.to_s.strip.empty?

      Time.parse(value.to_s).utc
    rescue ArgumentError
      nil
    end
    private_class_method :parse_time
  end
end
