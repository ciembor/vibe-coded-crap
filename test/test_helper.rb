$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))

require "json"
require "minitest/autorun"
require "stringio"
require "tmpdir"

require "helpdesk"

module HelpdeskTestSupport
  def reset_ticket_rules!
    Helpdesk::Ticket.sla_rules = Helpdesk::Ticket::DEFAULT_SLA_RULES
    Helpdesk::Ticket.escalation_rules = Helpdesk::Ticket::DEFAULT_ESCALATION_RULES
    Helpdesk::Ticket.workflows = Helpdesk::Ticket::DEFAULT_WORKFLOWS
  end

  def with_tmpdir
    Dir.mktmpdir("helpdesk-test-") do |dir|
      yield dir
    end
  end

  def capture_stdout
    original_stdout = $stdout
    output = StringIO.new
    $stdout = output
    yield
    output.string
  ensure
    $stdout = original_stdout
  end

  def build_cli(dir, role: "agent")
    store = Helpdesk::Store.new(path: File.join(dir, "tickets.json"))
    profiles = Helpdesk::ProfileStore.new(path: File.join(dir, "profiles.json"))
    context = Helpdesk::ApplicationContext.new(store: store, profiles: profiles)
    current_user = context.users.update(
      context.current_user.id,
      name: "Current",
      email: "current@example.test",
      role: role
    )
    context.current_user = current_user

    cli = Helpdesk::CLI.allocate
    cli.instance_variable_set(:@context, context)
    cli.send(:apply_context!)
    cli.instance_variable_set(:@api_rate_limit, Helpdesk::CLI::API_RATE_LIMIT)
    cli.instance_variable_set(:@api_rate_window_seconds, Helpdesk::CLI::API_RATE_WINDOW_SECONDS)
    cli.instance_variable_set(:@api_response_cache, {})
    cli.instance_variable_set(:@debug_enabled, false)
    cli
  end
end

class Minitest::Test
  include HelpdeskTestSupport
end
