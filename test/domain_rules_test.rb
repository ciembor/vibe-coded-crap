require "test_helper"

module Helpdesk
  class DomainRulesTest < Minitest::Test
    def test_dependency_blocks_closing_ticket
      with_tempdir do |dir|
        store = Store.new(path: File.join(dir, "tickets.json"))
        ticket = store.create(ticket_attrs(title: "Needs database"))
        dependency = store.create(ticket_attrs(title: "Database outage"))

        store.add_dependency(ticket.id, dependency.id)

        error = assert_raises(ArgumentError) do
          store.update(ticket.id, { status: "closed" }, actor_role: "agent")
        end

        assert_includes error.message, "open dependencies"
        assert_equal "open", store.find(ticket.id).status
      end
    end

    def test_relationships_are_symmetric
      with_tempdir do |dir|
        store = Store.new(path: File.join(dir, "tickets.json"))
        source = store.create(ticket_attrs(title: "Source"))
        target = store.create(ticket_attrs(title: "Target"))

        result = store.relate(source.id, target.id)

        refute_nil result
        assert_equal [target.id], store.find(source.id).related_ids
        assert_equal [source.id], store.find(target.id).related_ids
      end
    end

    def test_ticket_type_required_fields_are_validated
      with_tempdir do |dir|
        store = Store.new(path: File.join(dir, "tickets.json"))

        error = assert_raises(ArgumentError) do
          store.create(ticket_attrs(title: "Bug", ticket_type: "bug"))
        end

        assert_includes error.message, "severity"
      end
    end
  end
end
