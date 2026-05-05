require "time"
require "helpdesk/domain_normalization"

module Helpdesk
  class Template
    attr_accessor :name, :ticket_type, :title, :description, :status, :priority, :tags, :custom_fields, :created_at, :updated_at

    def self.from_h(hash)
      new(
        name: hash["name"],
        ticket_type: hash["ticket_type"],
        title: hash["title"],
        description: hash["description"],
        status: hash["status"],
        priority: hash["priority"],
        tags: hash["tags"] || [],
        custom_fields: hash["custom_fields"] || {},
        created_at: hash["created_at"],
        updated_at: hash["updated_at"]
      ).normalize!
    end

    def initialize(name: "", ticket_type: "general", title: "", description: "", status: "open", priority: "medium", tags: [], custom_fields: {}, created_at: nil, updated_at: nil)
      @name = name
      @ticket_type = ticket_type
      @title = title
      @description = description
      @status = status
      @priority = priority
      @tags = tags.dup
      @custom_fields = custom_fields
      @created_at = created_at
      @updated_at = updated_at
    end

    def normalize!
      self.name = DomainNormalization.present_string(name)
      raise ArgumentError, "template name cannot be empty" if name.empty?

      self.ticket_type = normalize_ticket_type(ticket_type)
      self.title = title.to_s
      self.description = description.to_s
      self.status = normalize_status(status)
      self.priority = normalize_priority(priority)
      self.tags = DomainNormalization.tags(tags)
      self.custom_fields = normalize_custom_fields(custom_fields)
      self.created_at ||= Time.now.utc.iso8601
      self.updated_at ||= created_at
      self
    end

    def update(attrs = {})
      self.name = DomainNormalization.present_string(attrs.fetch(:name, name))
      raise ArgumentError, "template name cannot be empty" if name.empty?

      self.ticket_type = normalize_ticket_type(attrs.fetch(:ticket_type, ticket_type))
      self.title = attrs.fetch(:title, title).to_s
      self.description = attrs.fetch(:description, description).to_s
      self.status = normalize_status(attrs.fetch(:status, status))
      self.priority = normalize_priority(attrs.fetch(:priority, priority))
      self.tags = DomainNormalization.tags(attrs.fetch(:tags, tags))
      self.custom_fields = normalize_custom_fields(attrs.fetch(:custom_fields, custom_fields))
      self.updated_at = Time.now.utc.iso8601
      self
    end

    def to_h
      {
        "name" => name,
        "ticket_type" => ticket_type,
        "title" => title,
        "description" => description,
        "status" => status,
        "priority" => priority,
        "tags" => tags,
        "custom_fields" => custom_fields,
        "created_at" => created_at,
        "updated_at" => updated_at
      }
    end

    private

    def normalize_ticket_type(value)
      normalized = DomainNormalization.present_string(value, downcase: true)
      normalized.empty? ? "general" : normalized
    end

    def normalize_status(value)
      DomainNormalization.enum(
        value,
        allowed: %w[open in_progress waiting resolved closed],
        default: "open",
        label: "status",
        strict: false
      )
    end

    def normalize_priority(value)
      DomainNormalization.enum(
        value,
        allowed: %w[low medium high urgent],
        default: "medium",
        label: "priority",
        strict: false
      )
    end

    def normalize_custom_fields(value)
      DomainNormalization.custom_fields(value)
    end
  end
end
