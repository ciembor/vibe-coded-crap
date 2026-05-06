require "fileutils"
require "helpdesk/api_token_store"
require "helpdesk/audit_log"
require "helpdesk/escalation_rule_store"
require "helpdesk/hook_store"
require "helpdesk/plugin_store"
require "helpdesk/profile_store"
require "helpdesk/session_store"
require "helpdesk/sla_rule_store"
require "helpdesk/sort_rule_store"
require "helpdesk/store"
require "helpdesk/template_store"
require "helpdesk/ticket"
require "helpdesk/user_store"
require "helpdesk/webhook_store"
require "helpdesk/workflow_store"

module Helpdesk
  class ApplicationContext
    attr_reader :profiles,
                :active_profile,
                :data_dir,
                :store,
                :audit_log,
                :escalation_rules,
                :sla_rules,
                :sort_rules,
                :templates,
                :users,
                :session,
                :api_tokens,
                :hooks,
                :plugins,
                :workflows,
                :webhooks,
                :current_user

    def initialize(store: nil, profiles: ProfileStore.new)
      @profiles = profiles
      @store = store
      reload!(force_profile_dir: store.nil?)
    end

    def reload!(force_profile_dir: false)
      @active_profile = profiles.active_profile || profiles.find("default")
      @data_dir = resolve_data_dir(force_profile_dir: force_profile_dir)
      FileUtils.mkdir_p(data_dir)

      @store = Store.new(path: data_path("tickets.json")) if force_profile_dir || store.nil?
      @audit_log = AuditLog.new(path: data_path("audit_log.json"))
      @escalation_rules = EscalationRuleStore.new(path: data_path("escalation_rules.json"))
      @sla_rules = SlaRuleStore.new(path: data_path("sla_rules.json"))
      @sort_rules = SortRuleStore.new(path: data_path("sort_rules.json"))
      @templates = TemplateStore.new(path: data_path("ticket_templates.json"))
      @users = UserStore.new(path: data_path("users.json"))
      @session = SessionStore.new(path: data_path("session.json"))
      @api_tokens = ApiTokenStore.new(path: data_path("api_tokens.json"))
      @hooks = HookStore.new(path: data_path("hooks.json"))
      @plugins = PluginStore.new(path: data_path("plugins.json"), config_path: data_path("plugins.config.json"))
      @workflows = WorkflowStore.new(path: data_path("workflows.json"))
      @webhooks = WebhookStore.new(path: data_path("webhooks.json"))

      reload_ticket_policies!
      seed_default_user!
      load_session_user!
      self
    end

    def current_user=(user)
      @current_user = user
      persist_current_user_session!
    end

    def clear_session_user!
      session.clear!
      self.current_user = users.all.first
    end

    def persist_current_user_session!
      session.current_user_id = current_user&.id if session
    end

    private

    def resolve_data_dir(force_profile_dir:)
      if force_profile_dir || store.nil?
        File.expand_path(active_profile ? active_profile["data_dir"] : default_data_dir)
      else
        File.expand_path(File.dirname(store.path))
      end
    end

    def default_data_dir
      File.expand_path("../../data", __dir__)
    end

    def data_path(filename)
      File.join(data_dir, filename)
    end

    def reload_ticket_policies!
      Ticket.workflows = workflows.to_workflow_hash
      escalation_rules.reload_ticket_rules!
      sla_rules.reload_ticket_rules!
    end

    def seed_default_user!
      users.create(name: "agent", email: "", role: "agent") if users.all.empty?
    end

    def load_session_user!
      user = users.find(session.current_user_id)
      user ||= users.all.first
      self.current_user = user
    end
  end
end
