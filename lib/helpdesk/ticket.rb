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
    end

    attr_accessor :id, :title, :description, :status, :priority, :tags, :comments, :internal_notes, :watchers, :attachments, :custom_fields, :ticket_type, :merged_into_id, :merged_from_ids, :pinned, :pinned_at, :archived, :archived_at, :created_at, :updated_at, :closed_at, :due_at, :reminder_at, :reminder_repeat

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

    def initialize(id: nil, title: "", description: "", status: "open", priority: "medium", tags: [], comments: [], internal_notes: [], watchers: [], attachments: [], custom_fields: {}, ticket_type: "general", merged_into_id: nil, merged_from_ids: [], pinned: false, pinned_at: nil, archived: false, archived_at: nil, created_at: nil, updated_at: nil, closed_at: nil, due_at: nil, reminder_at: nil, reminder_repeat: nil)
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
      self.status = normalize_status(status)
      self.priority = normalize_priority(priority)
      self.due_at = normalize_due_at(due_at)
      self.reminder_at = normalize_reminder_at(reminder_at)
      self.reminder_repeat = normalize_reminder_repeat(reminder_repeat)
      self.tags = Array(tags).map { |tag| tag.to_s.strip }.reject(&:empty?).uniq.sort
      self.ticket_type = normalize_ticket_type(ticket_type)
      self.merged_into_id = merged_into_id.to_i.zero? ? nil : merged_into_id.to_i
      self.merged_from_ids = Array(merged_from_ids).map(&:to_i).reject(&:zero?).uniq.sort
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
      self.status = normalize_status(attrs.fetch(:status, status))
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
      self.ticket_type = normalize_ticket_type(attrs.fetch(:ticket_type, ticket_type))
      self.merged_into_id = attrs.key?(:merged_into_id) ? attrs[:merged_into_id].to_i : merged_into_id.to_i
      self.merged_into_id = nil if self.merged_into_id.zero?
      self.merged_from_ids = Array(attrs.fetch(:merged_from_ids, merged_from_ids)).map(&:to_i).reject(&:zero?).uniq.sort
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

    def normalize_status(value)
      value = value.to_s.strip
      return "open" if value.empty?
      return value if STATUSES.include?(value)

      normalized = value.tr(" ", "_")
      return normalized if STATUSES.include?(normalized)

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
  end
end
