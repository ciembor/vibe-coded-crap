require "helpdesk/json_file"
require "helpdesk/hook_definition"

module Helpdesk
  class HookStore
    include JsonFileStore

    def initialize(path: default_path)
      configure_json_file(path, default: [])
    end

    def all
      load_data.sort_by { |row| row["id"].to_i }
    end

    def find(id)
      all.find { |hook| hook["id"].to_i == id.to_i }
    end

    def create(attrs)
      hooks = load_data
      hook = HookDefinition.create(id: next_id(hooks), attrs: attrs)
      hooks << hook
      save!(hooks)
      hook
    end

    def delete(id)
      hooks = load_data
      removed = hooks.reject! { |row| row["id"].to_i == id.to_i }
      save!(hooks) if removed
      !removed.nil?
    end

    def matching(event)
      all.select do |hook|
        HookDefinition.from_h(hook).matches?(event)
      end
    end

    private

    def default_path
      File.expand_path("../../data/hooks.json", __dir__)
    end

  end
end
