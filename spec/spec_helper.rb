require 'json'
require 'nypl_log_formatter'

require_relative '../lib/nypl_sierra_api_client'

ENV['LOG_LEVEL'] ||= 'error'
ENV['APP_ENV'] = 'test'

def load_fixture (file)
  JSON.parse File.read("./spec/fixtures/#{file}")
end
