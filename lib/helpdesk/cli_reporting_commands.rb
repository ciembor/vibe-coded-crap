require "csv"
require "date"
require "fileutils"
require "json"
require "time"
require "helpdesk/activity_presenter"
require "helpdesk/reporting_presenter"

module Helpdesk
  module CliReportingCommands
    def dashboard
      puts ReportingPresenter.dashboard(@store.all, duplicate_groups: @store.duplicate_groups)
    end

    alias stats dashboard

    def analytics(args)
      action = args[0]
      case action
      when nil, "summary"
        analytics_summary
      when "status"
        analytics_status
      when "aging"
        analytics_aging
      when "trend"
        analytics_trend
      else
        puts "Usage: analytics [summary|status|aging|trend]"
      end
    end

    def report(args)
      action = args[0]
      case action
      when "daily", nil
        report_daily(args[1])
      when "weekly"
        report_weekly(args[1])
      else
        puts "Usage: report daily [DATE] | report weekly [DATE]"
      end
    end

    def duplicates(args)
      options = parse_duplicate_options(args)
      if options[:ticket]
        ticket = @store.find(options[:ticket])
        return puts "Ticket not found." unless ticket

        puts ReportingPresenter.duplicate_candidates(ticket, @store.duplicate_candidates_for(ticket))
        return
      end

      puts ReportingPresenter.duplicate_groups(@store.duplicate_groups)
    end

    def export(args)
      format = args[0]
      case format
      when "csv"
        path = args[1] || prompt("CSV path", "data/tickets.csv")
        export_csv(path)
      when "json"
        path = args[1] || prompt("JSON path", "data/tickets-export.json")
        export_json(path)
      else
        puts "Usage: export csv [PATH] | export json [PATH]"
      end
    end

    def export_csv(path)
      tickets = @store.all
      FileUtils.mkdir_p(File.dirname(path))
      CSV.open(path, "w") do |csv|
        csv << %w[
          id title description status priority due_at overdue reminder_at reminder_repeat
          tags comment_count created_at updated_at closed_at
        ]
        tickets.each do |ticket|
          csv << [
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
      puts "Exported #{tickets.count} tickets to #{path}."
    end

    def export_json(path)
      tickets = @store.all
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, JSON.pretty_generate(tickets.map(&:to_h)))
      puts "Exported #{tickets.count} tickets to #{path}."
    end

    def import(args)
      return unless require_permission!(:admin)

      format = args[0]
      case format
      when "json"
        path = args[1] || prompt("JSON path", "data/tickets-export.json")
        summary = @store.import_json(path)
        report_duplicate_groups
        log_action("tickets.import", "tickets", source: path, imported: summary[:imported], merged: summary[:merged], remapped: summary[:remapped])
        puts "Imported #{summary[:imported]} tickets from #{path}."
        puts "Resolved #{summary[:merged]} duplicate merges and #{summary[:remapped]} ID conflicts."
      else
        puts "Usage: import json [PATH]"
      end
    rescue ArgumentError => e
      puts e.message
    end

    def audit(args)
      options = parse_audit_options(args)
      entries = @audit_log.all
      entries = entries.select { |entry| entry["action"] == options[:action] } if options[:action]
      entries = entries.select { |entry| entry["actor"].to_s.include?(options[:actor]) } if options[:actor]
      entries = entries.select { |entry| entry["subject"].to_s.include?(options[:subject]) } if options[:subject]
      entries = entries.last(options[:last]) if options[:last]
      if entries.empty?
        puts "No audit events."
        return
      end

      entries.each do |entry|
        puts "##{entry["id"]} #{entry["created_at"]} #{entry["actor"]} #{entry["action"]} #{entry["subject"]}"
      end
    end

    def activity(args)
      options = parse_activity_options(args)
      entries = @audit_log.all.select { |entry| ActivityPresenter.visible?(entry) }
      entries = entries.select { |entry| ActivityPresenter.for_ticket?(entry, options[:ticket]) } if options[:ticket]
      entries = entries.last(options[:last]) if options[:last]
      if entries.empty?
        puts "No activity."
        return
      end

      entries.each do |entry|
        puts ActivityPresenter.line(entry)
      end
    end

    def analytics_summary
      puts ReportingPresenter.analytics_summary(@store.all)
    end

    def analytics_status
      puts ReportingPresenter.analytics_status(@store.all)
    end

    def analytics_aging
      puts ReportingPresenter.analytics_aging(@store.all)
    end

    def analytics_trend
      puts ReportingPresenter.analytics_trend(@store.all)
    end

    def report_daily(date_string = nil)
      date = parse_report_date(date_string) || Date.today - 1
      puts ReportingPresenter.daily_report(@store.all, date)
    end

    def report_duplicate_candidates(ticket)
      candidates = @store.duplicate_candidates_for(ticket)
      return if candidates.empty?

      puts ReportingPresenter.duplicate_candidate_warning(ticket, candidates)
    end

    def report_duplicate_groups
      groups = @store.duplicate_groups
      return if groups.empty?

      puts ReportingPresenter.duplicate_group_warning(groups)
    end

    def report_weekly(date_string = nil)
      reference_date = parse_report_date(date_string) || Date.today - 7
      week_start = reference_date - (reference_date.wday - 1) % 7
      week_end = week_start + 6
      puts ReportingPresenter.weekly_report(@store.all, week_start, week_end)
    end

    def parse_report_date(value)
      return nil if value.to_s.strip.empty?

      Date.parse(value.to_s)
    rescue ArgumentError
      nil
    end

    def parse_duplicate_options(args)
      options = {}
      idx = 0
      while idx < args.length
        case args[idx]
        when "--ticket"
          options[:ticket] = args[idx + 1].to_i
          idx += 2
        else
          idx += 1
        end
      end
      options
    end

    def parse_audit_options(args)
      options = {}
      idx = 0
      while idx < args.length
        case args[idx]
        when "--last"
          options[:last] = args[idx + 1].to_i
          idx += 2
        when "--action"
          options[:action] = args[idx + 1]
          idx += 2
        when "--actor"
          options[:actor] = args[idx + 1]
          idx += 2
        when "--subject"
          options[:subject] = args[idx + 1]
          idx += 2
        else
          idx += 1
        end
      end
      options
    end

    def parse_activity_options(args)
      options = { last: 10 }
      idx = 0
      while idx < args.length
        case args[idx]
        when "--last"
          options[:last] = args[idx + 1].to_i
          idx += 2
        when "--ticket"
          options[:ticket] = args[idx + 1].to_i
          idx += 2
        else
          idx += 1
        end
      end
      options
    end

  end
end
