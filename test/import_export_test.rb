require "test_helper"

module Helpdesk
  class ImportExportTest < Minitest::Test
    def test_exports_tickets_as_json_and_csv
      with_tempdir do |dir|
        store = Store.new(path: File.join(dir, "tickets.json"))
        ticket = store.create(ticket_attrs(title: "Export me", tags: %w[export]))
        exporter = TicketExporter.new([ticket])
        json_path = File.join(dir, "exports", "tickets.json")
        csv_path = File.join(dir, "exports", "tickets.csv")

        assert_equal 1, exporter.export_json(json_path)
        assert_equal 1, exporter.export_csv(csv_path)

        exported_json = JSON.parse(File.read(json_path))
        exported_csv = File.read(csv_path)
        assert_equal "Export me", exported_json.first["title"]
        assert_includes exported_csv, "id,title,description,status,priority"
        assert_includes exported_csv, "Export me"
      end
    end

    def test_import_remaps_conflicting_ids
      with_tempdir do |dir|
        store = Store.new(path: File.join(dir, "tickets.json"))
        store.create(ticket_attrs(title: "Existing", description: "Original"))
        import_path = File.join(dir, "import.json")
        File.write(
          import_path,
          JSON.pretty_generate(
            [
              Ticket.new(
                id: 1,
                title: "Incoming",
                description: "Different",
                priority: "high"
              ).normalize!.to_h
            ]
          )
        )

        result = store.import_json(import_path)
        titles_by_id = store.all.sort_by(&:id).map { |ticket| [ticket.id, ticket.title] }

        assert_equal({ imported: 1, merged: 0, remapped: 1 }, result)
        assert_equal [[1, "Existing"], [2, "Incoming"]], titles_by_id
      end
    end

    def test_import_merges_duplicate_tickets
      with_tempdir do |dir|
        store = Store.new(path: File.join(dir, "tickets.json"))
        existing = store.create(ticket_attrs(title: "Same", description: "Body", priority: "low"))
        import_path = File.join(dir, "import.json")
        File.write(
          import_path,
          JSON.pretty_generate(
            [
              Ticket.new(
                id: 99,
                title: "Same",
                description: "Body",
                priority: "urgent",
                tags: ["incoming"]
              ).normalize!.to_h
            ]
          )
        )

        result = store.import_json(import_path)
        merged = store.find(existing.id)

        assert_equal({ imported: 1, merged: 1, remapped: 0 }, result)
        assert_equal 1, store.all.count
        assert_equal "urgent", merged.priority
        assert_equal ["incoming"], merged.tags
      end
    end
  end
end
