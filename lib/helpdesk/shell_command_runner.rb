module Helpdesk
  class ShellCommandRunner
    Result = Struct.new(:success, :exit_status, keyword_init: true)

    def run(env, command)
      success = system(env, command)
      status = $?.respond_to?(:exitstatus) ? $?.exitstatus : nil
      Result.new(success: success, exit_status: status)
    end
  end
end
