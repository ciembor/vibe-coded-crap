require 'simplecov'

SimpleCov.root Dir.pwd
SimpleCov.coverage_dir ENV.fetch('SIMPLECOV_COVERAGE_DIR', 'coverage')
SimpleCov.command_name ENV.fetch('SIMPLECOV_COMMAND_NAME', 'RSpec')

SimpleCov.start do
  add_filter '/spec/'
  add_filter '/test/'
  add_filter '/coverage/'
  add_filter '/tmp/'
  add_filter '/reports/'
end
