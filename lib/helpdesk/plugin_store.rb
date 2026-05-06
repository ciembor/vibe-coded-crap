require "json"
require "helpdesk/json_file"
require "helpdesk/plugin_definition"

module Helpdesk
  class PluginStore
    include JsonFileStore

    def initialize(path: default_path, config_path: default_config_path)
      @config_path = config_path
      configure_json_file(path, default: [])
    end

    def all
      (stored_plugins + config_data).uniq { |row| row["name"].to_s }.sort_by { |row| row["id"].to_i }
    end

    def find(id)
      all.find { |plugin| plugin["id"].to_i == id.to_i }
    end

    def find_by_name(name)
      all.find { |plugin| plugin["name"].to_s == name.to_s }
    end

    def create(attrs)
      plugins = load_data
      name = attrs.fetch(:name).to_s.strip
      raise ArgumentError, "plugin name cannot be empty" if name.empty?
      raise ArgumentError, "plugin name already exists" if all.any? { |row| row["name"].to_s == name }

      plugin = PluginDefinition.create(id: next_id(plugins), attrs: attrs)
      plugins << plugin
      save!(plugins)
      plugin
    end

    def delete(id)
      plugins = load_data
      removed = plugins.reject! { |row| row["id"].to_i == id.to_i }
      save!(plugins) if removed
      !removed.nil?
    end

    def run(name, args: [])
      plugin = find_by_name(name)
      return nil unless plugin
      definition = PluginDefinition.from_h(plugin)
      return nil unless definition.enabled?

      {
        plugin: plugin,
        command: definition.render_command(args)
      }
    end

    private

    def stored_plugins
      load_data.map { |row| PluginDefinition.from_h(row).to_h }
    end

    def default_path
      File.expand_path("../../data/plugins.json", __dir__)
    end

    def config_path
      @config_path || ENV.fetch("HELPDESK_PLUGINS_CONFIG", default_config_path)
    end

    def default_config_path
      File.expand_path("../../data/plugins.config.json", __dir__)
    end

    def config_data
      parsed = JSON.parse(File.read(config_path))
      rows = parsed.is_a?(Array) ? parsed : (parsed["plugins"] || parsed[:plugins] || [])
      Array(rows).map.with_index(1) do |row, idx|
        PluginDefinition.from_config(row, fallback_id: idx)
      end.compact
    rescue Errno::ENOENT, JSON::ParserError
      []
    end
  end
end
