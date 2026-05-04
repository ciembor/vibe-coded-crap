require "date"
require "time"

module Helpdesk
  class Ticket
    STATUSES = %w[open in_progress waiting resolved closed].freeze
    PRIORITIES = %w[low medium high urgent].freeze
    DEFAULT_SLA_RULES = {
      "low" => { warning_days: 14, breach_days: 21 },
      "medium" => { warning_days: 7, breach_days: 10 },
      "high" => { warning_days: 3, breach_days: 5 },
      "urgent" => { warning_days: 1, breach_days: 2 }
    }.freeze
    DEFAULT_ESCALATION_RULES = {
      "low" => { enabled: false, trigger: "sla_breached", target_role: "admin" },
      "medium" => { enabled: true, trigger: "sla_breached", target_role: "admin" },
      "high" => { enabled: true, trigger: "sla_warning", target_role: "admin" },
      "urgent" => { enabled: true, trigger: "overdue", target_role: "admin" }
    }.freeze
    DEFAULT_WORKFLOWS = {
      "general" => { name: "General", statuses: STATUSES, initial_status: "open" },
      "bug" => { name: "Bug", statuses: STATUSES, initial_status: "open" },
      "feature" => { name: "Feature", statuses: STATUSES, initial_status: "open" },
      "incident" => { name: "Incident", statuses: STATUSES, initial_status: "open" }
    }.freeze

    class << self
      def sla_rules
        @sla_rules ||= DEFAULT_SLA_RULES
      end

      def sla_rules=(rules)
        @sla_rules = normalize_sla_rules(rules)
      end

      def sla_rule_for(priority)
        sla_rules[priority.to_s]
      end

      def escalation_rules
        @escalation_rules ||= DEFAULT_ESCALATION_RULES
      end

      def escalation_rules=(rules)
        @escalation_rules = normalize_escalation_rules(rules)
      end

      def escalation_rule_for(priority)
        escalation_rules[priority.to_s]
      end

      def workflows
        @workflows ||= normalize_workflows(DEFAULT_WORKFLOWS)
      end

      def workflows=(workflows)
        @workflows = normalize_workflows(workflows)
      end

      def workflow_for(ticket_type)
        workflows[ticket_type.to_s] || workflows["general"]
      end

      def workflow_statuses_for(ticket_type)
        Array(workflow_for(ticket_type)["statuses"])
      end

      def initial_status_for(ticket_type)
        workflow_for(ticket_type)["initial_status"].to_s
      end

      private

      def normalize_sla_rules(rules)
        source = rules.is_a?(Hash) ? rules : {}
        PRIORITIES.each_with_object({}) do |priority, normalized|
          rule = source[priority] || source[priority.to_sym] || DEFAULT_SLA_RULES[priority]
          normalized[priority] = {
            warning_days: rule.fetch("warning_days", rule.fetch(:warning_days, DEFAULT_SLA_RULES[priority][:warning_days])).to_i,
            breach_days: rule.fetch("breach_days", rule.fetch(:breach_days, DEFAULT_SLA_RULES[priority][:breach_days])).to_i
          }
        end
      end

      def normalize_escalation_rules(rules)
        source = rules.is_a?(Hash) ? rules : {}
        PRIORITIES.each_with_object({}) do |priority, normalized|
          rule = source[priority] || source[priority.to_sym] || DEFAULT_ESCALATION_RULES[priority]
          normalized[priority] = {
            enabled: normalize_boolean(rule.fetch("enabled", rule.fetch(:enabled, DEFAULT_ESCALATION_RULES[priority][:enabled]))),
            trigger: normalize_escalation_trigger(rule.fetch("trigger", rule.fetch(:trigger, DEFAULT_ESCALATION_RULES[priority][:trigger]))),
            target_role: normalize_escalation_target_role(rule.fetch("target_role", rule.fetch(:target_role, DEFAULT_ESCALATION_RULES[priority][:target_role])))
          }
        end
      end

      def normalize_boolean(value)
        case value
        when true, false
          value
        else
          %w[true yes on 1].include?(value.to_s.strip.downcase)
        end
      end

      def normalize_escalation_trigger(value)
        value = value.to_s.strip.downcase
        value = "sla_breached" if value.empty?
        return value if %w[sla_warning sla_breached overdue].include?(value)

        raise ArgumentError, "invalid escalation trigger: #{value}"
      end

      def normalize_escalation_target_role(value)
        value = value.to_s.strip.downcase
        value = "admin" if value.empty?
        return value if %w[admin agent viewer].include?(value)

        raise ArgumentError, "invalid escalation target role: #{value}"
      end

      def normalize_workflows(workflows)
        source = workflows.is_a?(Hash) ? workflows : {}
        source.each_with_object({}) do |(ticket_type, workflow), normalized|
          ticket_type = ticket_type.to_s.strip
          next if ticket_type.empty?

          workflow = workflow.is_a?(Hash) ? workflow : {}
          statuses = normalize_workflow_statuses(workflow["statuses"] || workflow[:statuses] || STATUSES)
          initial_status = normalize_workflow_status(
            workflow["initial_status"] || workflow[:initial_status] || statuses.first || "open"
          )
          if statuses.empty?
            raise ArgumentError, "workflow #{ticket_type} must define at least one status"
          end
          unless statuses.include?("closed")
            raise ArgumentError, "workflow #{ticket_type} must include closed"
          end
          unless statuses.include?(initial_status)
            raise ArgumentError, "workflow #{ticket_type} initial status must be in statuses"
          end

          normalized[ticket_type] = {
            "name" => (workflow["name"] || workflow[:name] || ticket_type.tr("_", " ").capitalize).to_s,
            "statuses" => statuses,
            "initial_status" => initial_status
          }
        end
      end

      def normalize_workflow_statuses(statuses)
        Array(statuses).map { |status| normalize_workflow_status(status) }.reject(&:empty?).uniq
      end

      def normalize_workflow_status(status)
        value = status.to_s.strip
        return "" if value.empty?
        return value if value.match?(/\A[a-zA-Z0-9_]+\z/)

        value.tr(" ", "_")
      end
    end

    attr_accessor :id, :title, :description, :status, :priority, :tags, :comments, :internal_notes, :watchers, :attachments, :custom_fields, :ticket_type, :merged_into_id, :merged_from_ids, :related_ids, :parent_id, :child_ids, :dependency_ids, :pinned, :pinned_at, :archived, :archived_at, :created_at, :updated_at, :closed_at, :due_at, :reminder_at, :reminder_repeat

    def self.from_h(hash)
      ticket = new(
        id: hash["id"],
        title: hash["title"],
        description: hash["description"],
        status: hash["status"],
        priority: hash["priority"],
        tags: hash["tags"] || [],
        comments: hash["comments"] || [],
        internal_notes: hash["internal_notes"] || [],
        watchers: hash["watchers"] || [],
        attachments: hash["attachments"] || [],
        custom_fields: hash["custom_fields"] || {},
        ticket_type: hash["ticket_type"],
        merged_into_id: hash["merged_into_id"],
        merged_from_ids: hash["merged_from_ids"] || [],
        related_ids: hash["related_ids"] || [],
        parent_id: hash["parent_id"],
        child_ids: hash["child_ids"] || [],
        dependency_ids: hash["dependency_ids"] || [],
        pinned: hash["pinned"],
        pinned_at: hash["pinned_at"],
        archived: hash["archived"],
        archived_at: hash["archived_at"],
        created_at: hash["created_at"],
        updated_at: hash["updated_at"],
        closed_at: hash["closed_at"],
        due_at: hash["due_at"],
        reminder_at: hash["reminder_at"],
        reminder_repeat: hash["reminder_repeat"]
      )
      ticket.normalize!
      ticket
    end

    def initialize(id: nil, title: "", description: "", status: "open", priority: "medium", tags: [], comments: [], internal_notes: [], watchers: [], attachments: [], custom_fields: {}, ticket_type: "general", merged_into_id: nil, merged_from_ids: [], related_ids: [], parent_id: nil, child_ids: [], dependency_ids: [], pinned: false, pinned_at: nil, archived: false, archived_at: nil, created_at: nil, updated_at: nil, closed_at: nil, due_at: nil, reminder_at: nil, reminder_repeat: nil)
      @id = id
      @title = title
      @description = description
      @status = status
      @priority = priority
      @tags = tags.dup
      @comments = comments.dup
      @internal_notes = internal_notes.dup
      @watchers = watchers.dup
      @attachments = attachments.dup
      @custom_fields = custom_fields
      @ticket_type = ticket_type
      @merged_into_id = merged_into_id
      @merged_from_ids = merged_from_ids
      @related_ids = related_ids
      @parent_id = parent_id
      @child_ids = child_ids
      @dependency_ids = dependency_ids
      @pinned = pinned
      @pinned_at = pinned_at
      @archived = archived
      @archived_at = archived_at
      @created_at = created_at
      @updated_at = updated_at
      @closed_at = closed_at
      @due_at = due_at
      @reminder_at = reminder_at
      @reminder_repeat = reminder_repeat
    end

    def normalize!
      self.ticket_type = normalize_ticket_type(ticket_type)
      self.status = normalize_status(status, ticket_type: ticket_type)
      self.priority = normalize_priority(priority)
      self.due_at = normalize_due_at(due_at)
      self.reminder_at = normalize_reminder_at(reminder_at)
      self.reminder_repeat = normalize_reminder_repeat(reminder_repeat)
      self.tags = Array(tags).map { |tag| tag.to_s.strip }.reject(&:empty?).uniq.sort
      self.merged_into_id = merged_into_id.to_i.zero? ? nil : merged_into_id.to_i
      self.merged_from_ids = Array(merged_from_ids).map(&:to_i).reject(&:zero?).uniq.sort
      self.related_ids = Array(related_ids).map(&:to_i).reject(&:zero?).uniq.sort
      self.parent_id = parent_id.to_i.zero? ? nil : parent_id.to_i
      self.child_ids = Array(child_ids).map(&:to_i).reject(&:zero?).uniq.sort
      self.dependency_ids = Array(dependency_ids).map(&:to_i).reject(&:zero?).uniq.sort
      self.comments = Array(comments).map do |comment|
        {
          "id" => comment["id"] || comment[:id],
          "body" => comment["body"] || comment[:body],
          "author" => comment["author"] || comment[:author] || "agent",
          "created_at" => comment["created_at"] || comment[:created_at] || Time.now.utc.iso8601
        }
      end
      self.internal_notes = Array(internal_notes).map do |note|
        {
          "id" => note["id"] || note[:id],
          "body" => note["body"] || note[:body],
          "author" => note["author"] || note[:author] || "agent",
          "created_at" => note["created_at"] || note[:created_at] || Time.now.utc.iso8601
        }
      end
      self.watchers = Array(watchers).map { |watcher| watcher.to_i }.reject(&:zero?).uniq.sort
      self.attachments = Array(attachments).each_with_index.map do |attachment, index|
        {
          "id" => attachment["id"] || attachment[:id] || (index + 1),
          "name" => attachment["name"] || attachment[:name],
          "content_type" => attachment["content_type"] || attachment[:content_type] || "",
          "size" => (attachment["size"] || attachment[:size] || 0).to_i,
          "description" => attachment["description"] || attachment[:description] || "",
          "uploaded_by" => attachment["uploaded_by"] || attachment[:uploaded_by] || "agent",
          "created_at" => attachment["created_at"] || attachment[:created_at] || Time.now.utc.iso8601
        }
      end
      self.custom_fields = normalize_custom_fields(custom_fields)
      self.pinned = normalize_pinned(pinned)
      self.pinned_at = pinned? ? (pinned_at || Time.now.utc.iso8601) : nil
      self.archived = normalize_archived(archived)
      self.archived_at = archived? ? (archived_at || Time.now.utc.iso8601) : nil
      self.created_at ||= Time.now.utc.iso8601
      self.updated_at ||= created_at
      self.closed_at = nil unless closed?
      self
    end

    def update(attrs = {})
      self.title = attrs.fetch(:title, title)
      self.description = attrs.fetch(:description, description)
      new_ticket_type = normalize_ticket_type(attrs.fetch(:ticket_type, ticket_type))
      self.ticket_type = new_ticket_type
      self.status = normalize_status(attrs.fetch(:status, status), ticket_type: new_ticket_type)
      self.priority = normalize_priority(attrs.fetch(:priority, priority))
      self.due_at = normalize_due_at(attrs.fetch(:due_at, due_at))
      self.reminder_at = normalize_reminder_at(attrs.fetch(:reminder_at, reminder_at))
      self.reminder_repeat = normalize_reminder_repeat(attrs.fetch(:reminder_repeat, reminder_repeat))
      self.tags = Array(attrs.fetch(:tags, tags)).map { |tag| tag.to_s.strip }.reject(&:empty?).uniq.sort
      self.attachments = Array(attrs.fetch(:attachments, attachments)).each_with_index.map do |attachment, index|
        {
          "id" => attachment["id"] || attachment[:id] || (index + 1),
          "name" => attachment["name"] || attachment[:name],
          "content_type" => attachment["content_type"] || attachment[:content_type] || "",
          "size" => (attachment["size"] || attachment[:size] || 0).to_i,
          "description" => attachment["description"] || attachment[:description] || "",
          "uploaded_by" => attachment["uploaded_by"] || attachment[:uploaded_by] || "agent",
          "created_at" => attachment["created_at"] || attachment[:created_at] || Time.now.utc.iso8601
        }
      end
      self.custom_fields = normalize_custom_fields(attrs.fetch(:custom_fields, custom_fields))
      self.ticket_type = new_ticket_type
      self.merged_into_id = attrs.key?(:merged_into_id) ? attrs[:merged_into_id].to_i : merged_into_id.to_i
      self.merged_into_id = nil if self.merged_into_id.zero?
      self.merged_from_ids = Array(attrs.fetch(:merged_from_ids, merged_from_ids)).map(&:to_i).reject(&:zero?).uniq.sort
      self.related_ids = Array(attrs.fetch(:related_ids, related_ids)).map(&:to_i).reject(&:zero?).uniq.sort
      self.parent_id = attrs.key?(:parent_id) ? attrs[:parent_id].to_i : parent_id.to_i
      self.parent_id = nil if self.parent_id.zero?
      self.child_ids = Array(attrs.fetch(:child_ids, child_ids)).map(&:to_i).reject(&:zero?).uniq.sort
      self.dependency_ids = Array(attrs.fetch(:dependency_ids, dependency_ids)).map(&:to_i).reject(&:zero?).uniq.sort
      if attrs.key?(:pinned)
        self.pinned = !!attrs[:pinned]
        self.pinned_at = pinned? ? (attrs.fetch(:pinned_at, pinned_at) || Time.now.utc.iso8601) : nil
      end
      if attrs.key?(:archived)
        self.archived = !!attrs[:archived]
        self.archived_at = archived? ? (attrs.fetch(:archived_at, archived_at) || Time.now.utc.iso8601) : nil
      end
      self.updated_at = Time.now.utc.iso8601
      self.closed_at = Time.now.utc.iso8601 if closed?
      self.closed_at = nil unless closed?
      self
    end

    def add_comment(body:, author: "agent")
      self.comments << {
        "id" => next_comment_id,
        "body" => body,
        "author" => author,
        "created_at" => Time.now.utc.iso8601
      }
      self.updated_at = Time.now.utc.iso8601
    end

    def add_internal_note(body:, author: "agent")
      self.internal_notes << {
        "id" => next_internal_note_id,
        "body" => body,
        "author" => author,
        "created_at" => Time.now.utc.iso8601
      }
      self.updated_at = Time.now.utc.iso8601
    end

    def add_watcher(user_id)
      user_id = user_id.to_i
      return if user_id.zero?

      self.watchers = (watchers + [user_id]).uniq.sort
      self.updated_at = Time.now.utc.iso8601
    end

    def remove_watcher(user_id)
      user_id = user_id.to_i
      self.watchers = watchers.reject { |watcher_id| watcher_id.to_i == user_id }
      self.updated_at = Time.now.utc.iso8601
    end

    def add_tag(tag)
      tag = tag.to_s.strip
      return if tag.empty?

      self.tags = (tags + [tag]).map(&:strip).reject(&:empty?).uniq.sort
      self.updated_at = Time.now.utc.iso8601
    end

    def add_attachment(name:, content_type: "", size: 0, description: "", uploaded_by: "agent")
      name = name.to_s.strip
      return if name.empty?

      self.attachments << {
        "id" => next_attachment_id,
        "name" => name,
        "content_type" => content_type.to_s.strip,
        "size" => size.to_i,
        "description" => description.to_s.strip,
        "uploaded_by" => uploaded_by.to_s.strip.empty? ? "agent" : uploaded_by.to_s.strip,
        "created_at" => Time.now.utc.iso8601
      }
      self.attachments = attachments.sort_by { |attachment| attachment["id"].to_i }
      self.updated_at = Time.now.utc.iso8601
    end

    def set_custom_field(key, value)
      key = key.to_s.strip
      return if key.empty?

      self.custom_fields = (custom_fields || {}).merge(key => value.to_s)
      self.updated_at = Time.now.utc.iso8601
    end

    def remove_custom_field(key)
      key = key.to_s.strip
      return if key.empty?

      self.custom_fields = (custom_fields || {}).reject { |existing_key, _| existing_key.to_s.casecmp?(key) }
      self.updated_at = Time.now.utc.iso8601
    end

    def pin!
      self.pinned = true
      self.pinned_at = Time.now.utc.iso8601
      self.updated_at = Time.now.utc.iso8601
      self
    end

    def unpin!
      self.pinned = false
      self.pinned_at = nil
      self.updated_at = Time.now.utc.iso8601
      self
    end

    def archive!
      self.archived = true
      self.archived_at = Time.now.utc.iso8601
      self.updated_at = Time.now.utc.iso8601
      self
    end

    def unarchive!
      self.archived = false
      self.archived_at = nil
      self.updated_at = Time.now.utc.iso8601
      self
    end

    def remove_attachment(attachment_id)
      attachment_id = attachment_id.to_i
      original_count = attachments.count
      self.attachments = attachments.reject { |attachment| attachment["id"].to_i == attachment_id }
      return false if attachments.count == original_count

      self.updated_at = Time.now.utc.iso8601
      true
    end

    def remove_tag(tag)
      tag = tag.to_s.strip
      self.tags = tags.reject { |existing| existing.casecmp?(tag) }
      self.updated_at = Time.now.utc.iso8601
    end

    def closed?
      status == "closed"
    end

    def pinned?
      !!pinned
    end

    def archived?
      !!archived
    end

    def merged?
      !merged_into_id.nil?
    end

    def related?
      related_ids.any?
    end

    def parent?
      !parent_id.nil?
    end

    def child?
      child_ids.any?
    end

    def depends_on?
      dependency_ids.any?
    end

    def duplicate_key
      [normalized_duplicate_title, normalized_duplicate_description].join("|")
    end

    def duplicate_title_key
      normalized_duplicate_title
    end

    def valid_for_type?
      validation_errors.empty?
    end

    def validation_errors
      errors = []
      case ticket_type
      when "bug"
        errors << "bug tickets require a severity field" if custom_fields["severity"].to_s.strip.empty?
      when "feature"
        errors << "feature tickets require a requested_by field" if custom_fields["requested_by"].to_s.strip.empty?
      when "incident"
        errors << "incident tickets require an impact field" if custom_fields["impact"].to_s.strip.empty?
      end
      errors
    end

    def due_date
      return nil if due_at.to_s.strip.empty?

      Date.parse(due_at)
    rescue ArgumentError
      nil
    end

    def overdue?
      return false if closed? || status == "resolved"

      date = due_date
      date && date < Date.today
    end

    def sla_status(reference_time = Time.now.utc)
      return "none" if closed? || status == "resolved" || archived?

      age_days = sla_age_days(reference_time)
      return "none" unless age_days

      rule = sla_rule
      return "none" unless rule

      return "breached" if age_days >= rule[:breach_days]
      return "warning" if age_days >= rule[:warning_days]

      "ok"
    end

    def sla_warning?
      %w[warning breached].include?(sla_status)
    end

    def sla_breached?
      sla_status == "breached"
    end

    def sla_age_days(reference_time = Time.now.utc)
      ((reference_time - Time.parse(created_at)) / 86_400).floor
    rescue ArgumentError, TypeError
      nil
    end

    def sla_rule
      self.class.sla_rule_for(priority)
    end

    def escalation_rule
      self.class.escalation_rule_for(priority)
    end

    def escalation_status(reference_time = Time.now.utc)
      return "none" if closed? || status == "resolved" || archived?

      rule = escalation_rule
      return "none" unless rule && rule[:enabled]

      return "needed" if escalation_triggered?(rule, reference_time)

      "none"
    end

    def escalation_needed?
      escalation_status == "needed"
    end

    def escalation_target_role
      rule = escalation_rule
      rule ? rule[:target_role] : nil
    end

    def escalation_trigger
      rule = escalation_rule
      rule ? rule[:trigger] : nil
    end

    def escalation_triggered?(rule = escalation_rule, _reference_time = Time.now.utc)
      return false unless rule

      case rule[:trigger]
      when "sla_warning"
        sla_warning?
      when "sla_breached"
        sla_breached?
      when "overdue"
        overdue?
      else
        false
      end
    end

    def reminder_due?
      return false if closed?
      return false if reminder_at.to_s.strip.empty?

      Time.parse(reminder_at) <= Time.now.utc
    rescue ArgumentError
      false
    end

    def recurring_reminder?
      !reminder_repeat.to_s.strip.empty?
    end

    def advance_reminder!
      return self unless recurring_reminder?

      next_time =
        case reminder_repeat
        when "daily"
          Time.parse(reminder_at) + 86_400
        when "weekly"
          Time.parse(reminder_at) + 604_800
        when "monthly"
          Time.parse(reminder_at) + 2_592_000
        else
          nil
        end
      self.reminder_at = next_time&.utc&.iso8601
      self.updated_at = Time.now.utc.iso8601
      self
    rescue ArgumentError
      self.reminder_at = nil
      self
    end

    def to_h
      {
        "id" => id,
        "title" => title,
        "description" => description,
        "status" => status,
        "priority" => priority,
        "tags" => tags,
        "comments" => comments,
        "internal_notes" => internal_notes,
        "watchers" => watchers,
        "attachments" => attachments,
        "custom_fields" => custom_fields,
        "ticket_type" => ticket_type,
        "merged_into_id" => merged_into_id,
        "merged_from_ids" => merged_from_ids,
        "related_ids" => related_ids,
        "parent_id" => parent_id,
        "child_ids" => child_ids,
        "dependency_ids" => dependency_ids,
        "pinned" => pinned?,
        "pinned_at" => pinned_at,
        "archived" => archived?,
        "archived_at" => archived_at,
        "created_at" => created_at,
        "updated_at" => updated_at,
        "closed_at" => closed_at,
        "due_at" => due_at,
        "reminder_at" => reminder_at,
        "reminder_repeat" => reminder_repeat
      }
    end

    private

    def normalize_status(value, ticket_type: self.ticket_type)
      value = value.to_s.strip
      allowed = self.class.workflow_statuses_for(ticket_type)
      initial = self.class.initial_status_for(ticket_type)
      return initial if value.empty? && !initial.empty?
      return value if allowed.include?(value)

      normalized = value.tr(" ", "_")
      return normalized if allowed.include?(normalized)

      raise ArgumentError, "invalid status: #{value}"
    end

    def normalize_priority(value)
      value = value.to_s.strip
      return "medium" if value.empty?
      return value if PRIORITIES.include?(value)

      raise ArgumentError, "invalid priority: #{value}"
    end

    def normalize_due_at(value)
      value = value.to_s.strip
      return nil if value.empty?

      Date.parse(value).iso8601
    rescue ArgumentError
      raise ArgumentError, "invalid due date: #{value}"
    end

    def normalize_reminder_at(value)
      value = value.to_s.strip
      return nil if value.empty?

      Time.parse(value).utc.iso8601
    rescue ArgumentError
      raise ArgumentError, "invalid reminder time: #{value}"
    end

    def normalize_reminder_repeat(value)
      value = value.to_s.strip
      return nil if value.empty?

      return value if %w[daily weekly monthly].include?(value)

      raise ArgumentError, "invalid reminder repeat: #{value}"
    end

    def normalize_pinned(value)
      case value
      when true, false
        value
      when nil
        false
      else
        %w[true yes on 1].include?(value.to_s.strip.downcase)
      end
    end

    def normalize_archived(value)
      case value
      when true, false
        value
      when nil
        false
      else
        %w[true yes on 1].include?(value.to_s.strip.downcase)
      end
    end

    def normalize_custom_fields(value)
      hash = value.is_a?(Hash) ? value : {}
      hash.each_with_object({}) do |(key, val), normalized|
        key = key.to_s.strip
        next if key.empty?

        normalized[key] = val.to_s
      end
    end

    def merge_into!(target_id)
      self.merged_into_id = target_id.to_i
      self.archived = true
      self.archived_at = Time.now.utc.iso8601
      self.status = "closed"
      self.closed_at = Time.now.utc.iso8601
      self.updated_at = Time.now.utc.iso8601
      self
    end

    def add_merged_from(source_id)
      source_id = source_id.to_i
      return if source_id.zero?

      self.merged_from_ids = (merged_from_ids + [source_id]).uniq.sort
      self.updated_at = Time.now.utc.iso8601
    end

    def relate_to(ticket_id)
      ticket_id = ticket_id.to_i
      return if ticket_id.zero? || ticket_id == id.to_i

      self.related_ids = (related_ids + [ticket_id]).uniq.sort
      self.updated_at = Time.now.utc.iso8601
    end

    def unrelate(ticket_id)
      ticket_id = ticket_id.to_i
      self.related_ids = related_ids.reject { |existing_id| existing_id.to_i == ticket_id }
      self.updated_at = Time.now.utc.iso8601
    end

    def set_parent(ticket_id)
      ticket_id = ticket_id.to_i
      return if ticket_id.zero? || ticket_id == id.to_i

      self.parent_id = ticket_id
      self.updated_at = Time.now.utc.iso8601
    end

    def clear_parent
      self.parent_id = nil
      self.updated_at = Time.now.utc.iso8601
    end

    def add_child(ticket_id)
      ticket_id = ticket_id.to_i
      return if ticket_id.zero? || ticket_id == id.to_i

      self.child_ids = (child_ids + [ticket_id]).uniq.sort
      self.updated_at = Time.now.utc.iso8601
    end

    def remove_child(ticket_id)
      ticket_id = ticket_id.to_i
      self.child_ids = child_ids.reject { |existing_id| existing_id.to_i == ticket_id }
      self.updated_at = Time.now.utc.iso8601
    end

    def add_dependency(ticket_id)
      ticket_id = ticket_id.to_i
      return if ticket_id.zero? || ticket_id == id.to_i

      self.dependency_ids = (dependency_ids + [ticket_id]).uniq.sort
      self.updated_at = Time.now.utc.iso8601
    end

    def remove_dependency(ticket_id)
      ticket_id = ticket_id.to_i
      self.dependency_ids = dependency_ids.reject { |existing_id| existing_id.to_i == ticket_id }
      self.updated_at = Time.now.utc.iso8601
    end

    def normalize_ticket_type(value)
      value = value.to_s.strip.downcase
      value = "general" if value.empty?
      return value if %w[general bug feature incident].include?(value)

      raise ArgumentError, "invalid ticket type: #{value}"
    end

    def next_comment_id
      (comments.map { |comment| comment["id"].to_i }.max || 0) + 1
    end

    def next_internal_note_id
      (internal_notes.map { |note| note["id"].to_i }.max || 0) + 1
    end

    def next_attachment_id
      (attachments.map { |attachment| attachment["id"].to_i }.max || 0) + 1
    end

    def normalized_duplicate_title
      title.to_s.downcase.gsub(/[^a-z0-9]+/, " ").strip.squeeze(" ")
    end

    def normalized_duplicate_description
      description.to_s.downcase.gsub(/[^a-z0-9]+/, " ").strip.squeeze(" ")
    end
  end
end
