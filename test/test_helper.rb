$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))

require "json"
require "minitest/autorun"
require "tmpdir"

require "helpdesk"

module HelpdeskTestHelpers
  def with_tempdir
    Dir.mktmpdir("helpdesk-test-") do |dir|
      yield dir
    end
  end

  def ticket_attrs(title: "Ticket", description: "Description", **attrs)
    {
      title: title,
      description: description
    }.merge(attrs)
  end
end

class Minitest::Test
  include HelpdeskTestHelpers
end
