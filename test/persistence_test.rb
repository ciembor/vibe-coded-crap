require "test_helper"

module Helpdesk
  class PersistenceTest < Minitest::Test
    def test_store_creates_parent_directory_and_persists_tickets
      with_tempdir do |dir|
        path = File.join(dir, "nested", "tickets.json")
        store = Store.new(path: path)

        created = store.create(ticket_attrs(title: "Persist me", tags: [" billing ", "billing"]))
        reloaded = Store.new(path: path).find(created.id)

        assert File.exist?(path)
        assert_equal "Persist me", reloaded.title
        assert_equal ["billing"], reloaded.tags
      end
    end

    def test_invalid_json_loads_default_payload
      with_tempdir do |dir|
        path = File.join(dir, "tickets.json")
        File.write(path, "{")

        assert_empty Store.new(path: path).all
      end
    end

    def test_soft_delete_hides_tickets_unless_requested
      with_tempdir do |dir|
        store = Store.new(path: File.join(dir, "tickets.json"))
        ticket = store.create(ticket_attrs(title: "Delete me"))

        assert store.delete(ticket.id)

        assert_empty store.all
        assert_equal [ticket.id], store.all(include_deleted: true).map(&:id)
      end
    end
  end
end
