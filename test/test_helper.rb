$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))

require "fileutils"
require "minitest/autorun"
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
end

class Minitest::Test
  include HelpdeskTestSupport
end
