module Helpdesk
  class CliCommandRegistry
    Command = Struct.new(:name, :handler, :aliases, :permission, :terminal, keyword_init: true) do
      def call(cli, args)
        return :exit if terminal
        return :handled if permission && !cli.send(:require_permission!, permission)

        handler_method = cli.method(handler)
        if handler_method.arity.zero?
          handler_method.call
        else
          handler_method.call(args)
        end
        :handled
      end
    end

    def self.build(definitions)
      new(definitions.map { |definition| Command.new(**definition) })
    end

    def initialize(commands)
      @commands_by_name = {}
      @aliases = {}
      commands.each do |command|
        @commands_by_name[command.name] = command
        command.aliases.each { |command_alias| @aliases[command_alias] = command.name }
      end
    end

    def dispatch(cli, command_name, args)
      command = find(command_name)
      return nil unless command

      command.call(cli, args)
    end

    def aliases
      @aliases.sort.to_h
    end

    private

    def find(command_name)
      @commands_by_name[@aliases.fetch(command_name.to_s, command_name.to_s)]
    end
  end
end
