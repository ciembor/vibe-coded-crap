require "test_helper"

class ApplicationContextTest < Minitest::Test
  def setup
    reset_ticket_rules!
  end

  def test_context_builds_stores_from_active_profile
    with_tmpdir do |dir|
      profiles = Helpdesk::ProfileStore.new(path: File.join(dir, "profiles.json"))
      data_dir = File.join(dir, "team-data")
      profiles.upsert("team", "data_dir" => data_dir)
      profiles.set_active("team")

      context = Helpdesk::ApplicationContext.new(profiles: profiles)

      assert_equal File.expand_path(data_dir), context.data_dir
      assert_equal File.join(File.expand_path(data_dir), "tickets.json"), context.store.path
      assert_equal File.join(File.expand_path(data_dir), "session.json"), context.session.path
      assert_equal "team", context.active_profile["name"]
      assert_equal "agent", context.current_user.name
      assert_equal context.current_user.id, context.session.current_user_id
    end
  end

  def test_context_uses_injected_store_directory_until_profile_reload_is_forced
    with_tmpdir do |dir|
      profiles = Helpdesk::ProfileStore.new(path: File.join(dir, "profiles.json"))
      profile_dir = File.join(dir, "profile-data")
      profiles.upsert("team", "data_dir" => profile_dir)
      profiles.set_active("team")
      store_dir = File.join(dir, "external-store")
      store = Helpdesk::Store.new(path: File.join(store_dir, "tickets.json"))

      context = Helpdesk::ApplicationContext.new(store: store, profiles: profiles)

      assert_same store, context.store
      assert_equal File.expand_path(store_dir), context.data_dir

      context.reload!(force_profile_dir: true)

      assert_equal File.expand_path(profile_dir), context.data_dir
      assert_equal File.join(File.expand_path(profile_dir), "tickets.json"), context.store.path
    end
  end

  def test_context_persists_current_session_user
    with_tmpdir do |dir|
      profiles = Helpdesk::ProfileStore.new(path: File.join(dir, "profiles.json"))
      data_dir = File.join(dir, "data")
      profiles.upsert("team", "data_dir" => data_dir)
      profiles.set_active("team")
      context = Helpdesk::ApplicationContext.new(profiles: profiles)
      user = context.users.create(name: "Triage", email: "triage@example.test", role: "admin")

      context.current_user = user

      assert_equal user.id, context.session.current_user_id
      reloaded = Helpdesk::ApplicationContext.new(profiles: profiles)
      assert_equal user.id, reloaded.current_user.id
    end
  end
end
