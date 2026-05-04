require "json"
require "fileutils"
require "helpdesk/ticket"

module Helpdesk
  class WorkflowStore
    attr_reader :path

    def initialize(path: default_path)
      @path = path
      FileUtils.mkdir_p(File.dirname(path))
      save!(default_rows) unless File.exist?(path)
    end

    def all
      load_data.sort_by { |row| row["ticket_type"].to_s }
    end

    def find(ticket_type)
      all.find { |workflow| workflow["ticket_type"].to_s == ticket_type.to_s }
    end

    def upsert(ticket_type, attrs)
      rows = load_data
      workflow = normalize_workflow(
        ticket_type,
        "name" => attrs[:name] || attrs["name"] || ticket_type.to_s,
        "statuses" => attrs[:statuses] || attrs["statuses"] || [],
        "initial_status" => attrs[:initial_status] || attrs["initial_status"],
        "transitions" => attrs[:transitions] || attrs["transitions"]
      )

      index = rows.index { |row| row["ticket_type"].to_s == workflow["ticket_type"] }
      if index
        rows[index] = workflow
      else
        rows << workflow
      end
      save!(rows)
      workflow
    end

    def reset(ticket_type = nil)
      rows = load_data
      if ticket_type.nil? || ticket_type.to_s == "all"
        save!(default_rows)
        return default_rows
      end

      ticket_type = ticket_type.to_s
      rows.reject! { |row| row["ticket_type"].to_s == ticket_type }
      rows << default_workflows[ticket_type] if default_workflows.key?(ticket_type)
      save!(rows.empty? ? default_rows : rows)
    end

    def transitions_for(ticket_type)
      find(ticket_type).to_h.fetch("transitions", {})
    end

    def set_transition(ticket_type, from_status, next_statuses)
      rows = load_data
      index = rows.index { |row| row["ticket_type"].to_s == ticket_type.to_s }
      return nil unless index

      workflow = normalize_workflow(
        ticket_type,
        rows[index].merge("transitions" => (rows[index]["transitions"] || {}).merge(from_status.to_s => next_statuses))
      )
      rows[index] = workflow
      save!(rows)
      workflow
    end

    def reset_transitions(ticket_type = nil)
      rows = load_data
      if ticket_type.nil? || ticket_type.to_s == "all"
        rows.map! do |row|
          normalize_workflow(row["ticket_type"], row.merge("transitions" => default_transitions(row["statuses"] || [])))
        end
        save!(rows)
        return rows
      end

      ticket_type = ticket_type.to_s
      index = rows.index { |row| row["ticket_type"].to_s == ticket_type }
      return nil unless index

      rows[index] = normalize_workflow(ticket_type, rows[index].merge("transitions" => default_transitions(rows[index]["statuses"] || [])))
      save!(rows)
      rows[index]
    end

    def to_workflow_hash
      all.each_with_object({}) do |row, normalized|
        normalized[row["ticket_type"]] = {
          "name" => row["name"],
          "statuses" => row["statuses"],
          "initial_status" => row["initial_status"],
          "transitions" => row["transitions"] || {}
        }
      end
    end

    private

    def default_path
      File.expand_path("../../data/workflows.json", __dir__)
    end

    def default_workflows
      Ticket::DEFAULT_WORKFLOWS.each_with_object({}) do |(ticket_type, workflow), normalized|
        normalized[ticket_type] = normalize_workflow(ticket_type, workflow)
      end
    end

    def default_rows
      default_workflows.values
    end

    def normalize_workflow(ticket_type, attrs)
      ticket_type = ticket_type.to_s.strip
      raise ArgumentError, "ticket type cannot be empty" if ticket_type.empty?

      statuses = Array(attrs["statuses"] || attrs[:statuses]).map { |status| status.to_s.strip }.reject(&:empty?).uniq
      statuses = Ticket::STATUSES if statuses.empty?
      initial_status = (attrs["initial_status"] || attrs[:initial_status] || statuses.first || "open").to_s.strip
      initial_status = statuses.first if initial_status.empty?
      raise ArgumentError, "workflow #{ticket_type} must include closed" unless statuses.include?("closed")
      raise ArgumentError, "workflow #{ticket_type} initial status must be in statuses" unless statuses.include?(initial_status)
      transitions = normalize_transitions(attrs["transitions"] || attrs[:transitions] || default_transitions(statuses), statuses, ticket_type)

      {
        "ticket_type" => ticket_type,
        "name" => (attrs["name"] || attrs[:name] || ticket_type.tr("_", " ").capitalize).to_s.strip,
        "statuses" => statuses,
        "initial_status" => initial_status,
        "transitions" => transitions
      }
    end

    def default_transitions(statuses)
      statuses.each_cons(2).each_with_object({}) do |(from_status, to_status), normalized|
        normalized[from_status] ||= []
        normalized[from_status] << to_status
      end
    end

    def normalize_transitions(transitions, statuses, ticket_type)
      source = transitions.is_a?(Hash) ? transitions : {}
      source.each_with_object({}) do |(from_status, next_statuses), normalized|
        from_status = from_status.to_s.strip
        next if from_status.empty?
        raise ArgumentError, "workflow #{ticket_type} has invalid transition source: #{from_status}" unless statuses.include?(from_status)

        normalized[from_status] = Array(next_statuses).map { |status| status.to_s.strip }.reject(&:empty?).uniq
        invalid = normalized[from_status] - statuses
        raise ArgumentError, "workflow #{ticket_type} has invalid transition targets: #{invalid.join(', ')}" if invalid.any?
      end
    end

    def load_data
      JSON.parse(File.read(path))
    rescue Errno::ENOENT, JSON::ParserError
      []
    end

    def save!(rows)
      File.write(path, JSON.pretty_generate(rows))
    end
  end
end
