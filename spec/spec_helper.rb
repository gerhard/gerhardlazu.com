PADRINO_ENV = 'test' unless defined?(PADRINO_ENV)
require File.expand_path(File.dirname(__FILE__) + "/../config/boot")

RSpec.configure do |config|
  config.include Rack::Test::Methods
end

def app
  ##
  # You can handle all padrino applications using instead:
  #   Padrino.application
  Gerhardlazu.tap { |app| }
end

Gerhardlazu.setup_application!