require "test_helper"

class StoreTest < Minitest::Test
  def setup
    reset_ticket_rules!
  end

  def test_blocks_closing_tickets_with_open_dependencies
    with_tmpdir do |dir|
      store = Helpdesk::Store.new(path: File.join(dir, "tickets.json"))
      dependency = store.create(title: "Finish migration")
      ticket = store.create(title: "Launch feature")

      store.add_dependency(ticket.id, dependency.id)

      error = assert_raises(ArgumentError) do
        store.update(ticket.id, { status: "closed" }, actor_role: "admin")
      end
      assert_match(/open dependencies/, error.message)

      store.update(dependency.id, { status: "closed" }, actor_role: "admin")
      closed = store.update(ticket.id, { status: "closed" }, actor_role: "admin")

      assert_equal "closed", closed.status
    end
  end

  def test_import_merges_duplicate_ticket_content
    with_tmpdir do |dir|
      store = Helpdesk::Store.new(path: File.join(dir, "tickets.json"))
      existing = store.create(title: "Cannot login", description: "SSO is failing")
      import_path = File.join(dir, "import.json")
      File.write(import_path, JSON.pretty_generate([
        existing.to_h.merge(
          "id" => 99,
          "comments" => [{ "id" => 1, "body" => "Customer is blocked", "author" => "agent" }],
          "tags" => ["urgent"]
        )
      ]))

      result = store.import_json(import_path)
      ticket = store.find(existing.id)

      assert_equal({ imported: 1, merged: 1, remapped: 0 }, result)
      assert_includes ticket.tags, "urgent"
      assert_match(/Imported from #99/, ticket.comments.first["body"])
    end
  end
end
