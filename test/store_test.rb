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
      existing = store.create(title: "Cannot login", description: "SSO fails")
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

  def test_import_remaps_id_conflicts_without_overwriting_existing_ticket
    with_tmpdir do |dir|
      store = Helpdesk::Store.new(path: File.join(dir, "tickets.json"))
      existing = store.create(title: "Existing ticket", description: "Keep this")
      import_path = File.join(dir, "conflict-import.json")
      File.write(import_path, JSON.pretty_generate([
        existing.to_h.merge(
          "id" => existing.id,
          "title" => "Imported different ticket",
          "description" => "Do not overwrite"
        )
      ]))

      result = store.import_json(import_path)
      tickets = store.all
      imported = tickets.find { |ticket| ticket.title == "Imported different ticket" }

      assert_equal({ imported: 1, merged: 0, remapped: 1 }, result)
      assert_equal "Existing ticket", store.find(existing.id).title
      refute_nil imported
      refute_equal existing.id, imported.id
    end
  end

  def test_relationships_keep_bidirectional_links_and_move_parent_links
    with_tmpdir do |dir|
      store = Helpdesk::Store.new(path: File.join(dir, "tickets.json"))
      first_parent = store.create(title: "First parent")
      second_parent = store.create(title: "Second parent")
      child = store.create(title: "Child")
      peer = store.create(title: "Peer")

      store.relate(child.id, peer.id)
      store.set_parent(child.id, first_parent.id)
      store.set_parent(child.id, second_parent.id)

      child = store.find(child.id)
      peer = store.find(peer.id)
      first_parent = store.find(first_parent.id)
      second_parent = store.find(second_parent.id)

      assert_includes child.related_ids, peer.id
      assert_includes peer.related_ids, child.id
      assert_equal second_parent.id, child.parent_id
      refute_includes first_parent.child_ids, child.id
      assert_includes second_parent.child_ids, child.id
    end
  end
end
