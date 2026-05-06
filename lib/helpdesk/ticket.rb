require "time"
require "helpdesk/ticket_policy"
require "helpdesk/ticket_attachment"
require "helpdesk/ticket_entry"

module Helpdesk
  class Ticket
    STATUSES = TicketPolicy::STATUSES
    PRIORITIES = TicketPolicy::PRIORITIES
    DEFAULT_SLA_RULES = TicketPolicy::DEFAULT_SLA_RULES
    DEFAULT_ESCALATION_RULES = TicketPolicy::DEFAULT_ESCALATION_RULES
    DEFAULT_WORKFLOWS = TicketPolicy::DEFAULT_WORKFLOWS
    DEFAULT_TRANSITION_ROLES = TicketPolicy::DEFAULT_TRANSITION_ROLES

    class << self
      def policy
        @policy ||= TicketPolicy.new
      end

      def policy=(policy)
        @policy = policy
      end

      def sla_rules
        policy.sla_rules
      end

      def sla_rules=(rules)
        policy.sla_rules = rules
      end

      def sla_rule_for(priority)
        policy.sla_rule_for(priority)
      end

      def escalation_rules
        policy.escalation_rules
      end

      def escalation_rules=(rules)
        policy.escalation_rules = rules
      end

      def escalation_rule_for(priority)
        policy.escalation_rule_for(priority)
      end

      def workflows
        policy.workflows
      end

      def workflows=(workflows)
        policy.workflows = workflows
      end

      def workflow_for(ticket_type)
        policy.workflow_for(ticket_type)
      end

      def workflow_statuses_for(ticket_type)
        policy.workflow_statuses_for(ticket_type)
      end

      def initial_status_for(ticket_type)
        policy.initial_status_for(ticket_type)
      end

      def workflow_transitions_for(ticket_type)
        policy.workflow_transitions_for(ticket_type)
      end

      def workflow_next_statuses_for(ticket_type, status)
        policy.workflow_next_statuses_for(ticket_type, status)
      end

      def workflow_transition_permissions_for(ticket_type)
        policy.workflow_transition_permissions_for(ticket_type)
      end

      def workflow_transition_roles_for(ticket_type, from_status, to_status)
        policy.workflow_transition_roles_for(ticket_type, from_status, to_status)
      end

      def workflow_transition_allowed?(ticket_type, from_status, to_status, role)
        policy.workflow_transition_allowed?(ticket_type, from_status, to_status, role)
      end
    end

    attr_accessor :id, :title, :description, :status, :priority, :tags, :comments, :internal_notes, :watchers, :attachments, :custom_fields, :ticket_type, :merged_into_id, :merged_from_ids, :related_ids, :parent_id, :child_ids, :dependency_ids, :pinned, :pinned_at, :archived, :archived_at, :deleted, :deleted_at, :created_at, :updated_at, :closed_at, :due_at, :reminder_at, :reminder_repeat

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
        deleted: hash["deleted"],
        deleted_at: hash["deleted_at"],
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

    def initialize(id: nil, title: "", description: "", status: "open", priority: "medium", tags: [], comments: [], internal_notes: [], watchers: [], attachments: [], custom_fields: {}, ticket_type: "general", merged_into_id: nil, merged_from_ids: [], related_ids: [], parent_id: nil, child_ids: [], dependency_ids: [], pinned: false, pinned_at: nil, archived: false, archived_at: nil, deleted: false, deleted_at: nil, created_at: nil, updated_at: nil, closed_at: nil, due_at: nil, reminder_at: nil, reminder_repeat: nil)
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
      @deleted = deleted
      @deleted_at = deleted_at
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
      now = Time.now.utc
      self.comments = TicketEntry.normalize_many(comments, now: now)
      self.internal_notes = TicketEntry.normalize_many(internal_notes, now: now)
      self.watchers = Array(watchers).map { |watcher| watcher.to_i }.reject(&:zero?).uniq.sort
      self.attachments = TicketAttachment.normalize_many(attachments, now: now)
      self.custom_fields = normalize_custom_fields(custom_fields)
      self.pinned = normalize_pinned(pinned)
      self.pinned_at = pinned? ? (pinned_at || Time.now.utc.iso8601) : nil
      self.archived = normalize_archived(archived)
      self.archived_at = archived? ? (archived_at || Time.now.utc.iso8601) : nil
      self.deleted = normalize_deleted(deleted)
      self.deleted_at = deleted? ? (deleted_at || Time.now.utc.iso8601) : nil
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
      self.attachments = TicketAttachment.normalize_many(attrs.fetch(:attachments, attachments))
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
      if attrs.key?(:deleted)
        self.deleted = !!attrs[:deleted]
        self.deleted_at = deleted? ? (attrs.fetch(:deleted_at, deleted_at) || Time.now.utc.iso8601) : nil
      end
      self.updated_at = Time.now.utc.iso8601
      self.closed_at = Time.now.utc.iso8601 if closed?
      self.closed_at = nil unless closed?
      self
    end

    def add_comment(body:, author: "agent")
      self.comments << TicketEntry.build(comments, body: body, author: author)
      self.updated_at = Time.now.utc.iso8601
    end

    def add_internal_note(body:, author: "agent")
      self.internal_notes << TicketEntry.build(internal_notes, body: body, author: author)
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

      self.attachments << TicketAttachment.build(
        attachments,
        name: name,
        content_type: content_type,
        size: size,
        description: description,
        uploaded_by: uploaded_by
      )
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

    def delete!
      self.deleted = true
      self.deleted_at = Time.now.utc.iso8601
      self.updated_at = Time.now.utc.iso8601
      self
    end

    def restore_deleted!
      self.deleted = false
      self.deleted_at = nil
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

    def deleted?
      !!deleted
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
      self.class.policy.duplicate_key(self)
    end

    def duplicate_title_key
      self.class.policy.duplicate_title_key(self)
    end

    def valid_for_type?
      validation_errors.empty?
    end

    def validation_errors
      self.class.policy.validation_errors(self)
    end

    def due_date
      self.class.policy.due_date(self)
    end

    def overdue?
      self.class.policy.overdue?(self)
    end

    def sla_status(reference_time = Time.now.utc)
      self.class.policy.sla_status(self, reference_time)
    end

    def sla_warning?
      self.class.policy.sla_warning?(self)
    end

    def sla_breached?
      self.class.policy.sla_breached?(self)
    end

    def sla_age_days(reference_time = Time.now.utc)
      self.class.policy.sla_age_days(self, reference_time)
    end

    def sla_rule
      self.class.policy.sla_rule(self)
    end

    def escalation_rule
      self.class.policy.escalation_rule(self)
    end

    def escalation_status(reference_time = Time.now.utc)
      self.class.policy.escalation_status(self, reference_time)
    end

    def escalation_needed?
      self.class.policy.escalation_needed?(self)
    end

    def escalation_target_role
      self.class.policy.escalation_target_role(self)
    end

    def escalation_trigger
      self.class.policy.escalation_trigger(self)
    end

    def can_transition_to?(to_status, role: nil)
      self.class.policy.can_transition?(self, to_status, role: role)
    end

    def escalation_triggered?(rule = escalation_rule, _reference_time = Time.now.utc)
      self.class.policy.escalation_triggered?(self, rule)
    end

    def reminder_due?
      self.class.policy.reminder_due?(self)
    end

    def recurring_reminder?
      self.class.policy.recurring_reminder?(self)
    end

    def advance_reminder!
      self.class.policy.advance_reminder!(self)
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
        "deleted" => deleted?,
        "deleted_at" => deleted_at,
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
      self.class.policy.normalize_status(value, ticket_type: ticket_type)
    end

    def normalize_priority(value)
      self.class.policy.normalize_priority(value)
    end

    def normalize_due_at(value)
      self.class.policy.normalize_due_at(value)
    end

    def normalize_reminder_at(value)
      self.class.policy.normalize_reminder_at(value)
    end

    def normalize_reminder_repeat(value)
      self.class.policy.normalize_reminder_repeat(value)
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

    def normalize_deleted(value)
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
      self.class.policy.normalize_ticket_type(value)
    end
  end
end
