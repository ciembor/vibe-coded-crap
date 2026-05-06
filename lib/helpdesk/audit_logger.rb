module Helpdesk
  class AuditLogger
    def initialize(audit_log:, integration_dispatcher:, debug_logger:)
      @audit_log = audit_log
      @integration_dispatcher = integration_dispatcher
      @debug_logger = debug_logger
    end

    def log(action, subject, details:, actor:)
      @debug_logger.log("action=#{action} actor=#{actor} subject=#{subject} details=#{details.inspect}")
      @audit_log.append(action: action, actor: actor, subject: subject, details: details)
      @integration_dispatcher.dispatch(action, actor, subject, details)
    end
  end
end
