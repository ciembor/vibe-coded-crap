require "date"
require "time"

module Helpdesk
  class Ticket
    STATUSES = %w[open in_progress waiting resolved closed].freeze
    PRIORITIES = %w[low medium high urgent].freeze

    attr_accessor :id, :title, :description, :status, :priority, :tags, :comments, :internal_notes, :watchers, :created_at, :updated_at, :closed_at, :due_at, :reminder_at, :reminder_repeat

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

    def initialize(id: nil, title: "", description: "", status: "open", priority: "medium", tags: [], comments: [], internal_notes: [], watchers: [], created_at: nil, updated_at: nil, closed_at: nil, due_at: nil, reminder_at: nil, reminder_repeat: nil)
      @id = id
      @title = title
      @description = description
      @status = status
      @priority = priority
      @tags = tags.dup
      @comments = comments.dup
      @internal_notes = internal_notes.dup
      @watchers = watchers.dup
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

    def remove_tag(tag)
      tag = tag.to_s.strip
      self.tags = tags.reject { |existing| existing.casecmp?(tag) }
      self.updated_at = Time.now.utc.iso8601
    end

    def closed?
      status == "closed"
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

    def next_comment_id
      (comments.map { |comment| comment["id"].to_i }.max || 0) + 1
    end

    def next_internal_note_id
      (internal_notes.map { |note| note["id"].to_i }.max || 0) + 1
    end
  end
end
