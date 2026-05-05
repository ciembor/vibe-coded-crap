require "helpdesk/json_file"
require "helpdesk/webhook_definition"

module Helpdesk
  class WebhookStore
    include JsonFileStore

    def initialize(path: default_path)
      configure_json_file(path, default: [])
    end

    def all
      load_data.sort_by { |row| row["id"].to_i }
    end

    def find(id)
      all.find { |webhook| webhook["id"].to_i == id.to_i }
    end

    def create(attrs)
      webhooks = load_data
      webhook = WebhookDefinition.create(id: next_id(webhooks), attrs: attrs)
      webhooks << webhook
      save!(webhooks)
      webhook
    end

    def delete(id)
      webhooks = load_data
      removed = webhooks.reject! { |row| row["id"].to_i == id.to_i }
      save!(webhooks) if removed
      !removed.nil?
    end

    def update(id, attrs)
      webhooks = load_data
      index = webhooks.index { |row| row["id"].to_i == id.to_i }
      return nil unless index

      webhook = WebhookDefinition.from_h(webhooks[index]).update(attrs)
      webhooks[index] = webhook
      save!(webhooks)
      webhook
    end

    def matching(event)
      all.select do |webhook|
        WebhookDefinition.from_h(webhook).matches?(event)
      end
    end

    private

    def default_path
      File.expand_path("../../data/webhooks.json", __dir__)
    end

  end
end
