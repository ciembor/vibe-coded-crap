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
end

class Minitest::Test
  include HelpdeskTestSupport
end
