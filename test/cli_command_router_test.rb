require "test_helper"

module Helpdesk
  class CliCommandRouterTest < Minitest::Test
    class RecordingCli
      attr_reader :calls

      def initialize
        @calls = []
      end

      private

      def no_args
        @calls << [:no_args]
      end

      def with_args(args)
        @calls << [:with_args, args]
      end
    end

    class RecordingHandler
      def initialize(method_name, passes_args:)
        @method_name = method_name
        @passes_args = passes_args
      end

      def call(cli, args)
        @passes_args ? cli.send(@method_name, args) : cli.send(@method_name)
      end
    end

    def test_dispatches_handler_without_args
      cli = RecordingCli.new
      router = CliCommandRouter.new(
        routes: {
          "ping" => RecordingHandler.new(:no_args, passes_args: false)
        }
      )

      assert_equal :handled, router.dispatch(cli, "ping", ["ignored"])
      assert_equal [[:no_args]], cli.calls
    end

    def test_dispatches_handler_with_args
      cli = RecordingCli.new
      router = CliCommandRouter.new(
        routes: {
          "echo" => RecordingHandler.new(:with_args, passes_args: true)
        }
      )

      assert_equal :handled, router.dispatch(cli, "echo", ["one", "two"])
      assert_equal [[:with_args, ["one", "two"]]], cli.calls
    end

    def test_reports_exit_and_unknown_commands
      router = CliCommandRouter.new(routes: {})

      assert_equal :exit, router.dispatch(Object.new, "exit", [])
      assert_equal :unknown, router.dispatch(Object.new, "missing", [])
    end
  end
end
