require 'net/http'
require 'net/https'
require 'uri'
require 'nypl_log_formatter'

require_relative 'errors'
require_relative 'sierra_api_response'

class SierraApiClient
  def initialize(config = {})
    @config = {
      base_url: ENV['SIERRA_API_BASE_URL'],
      client_id: ENV['SIERRA_OAUTH_ID'],
      client_secret: ENV['SIERRA_OAUTH_SECRET'],
      oauth_url: ENV['SIERRA_OAUTH_URL'],
      log_level: 'info'
    }.merge config

    raise SierraApiClientError.new 'Missing config: neither config.base_url nor ENV.SIERRA_API_BASE_URL are set' unless @config[:base_url]
    raise SierraApiClientError.new 'Missing config: neither config.client_id nor ENV.SIERRA_OAUTH_ID are set' unless @config[:client_id]
    raise SierraApiClientError.new 'Missing config: neither config.client_secret nor ENV.SIERRA_OAUTH_SECRET are set ' unless @config[:client_secret]
    raise SierraApiClientError.new 'Missing config: neither config.oauth_url nor ENV.SIERRA_OAUTH_URL are set ' unless @config[:oauth_url]
  end

  def get (path, options = {})
    options = parse_http_options options

    do_request 'get', path, options
  end

  def post (path, body, options = {})
    options = parse_http_options options

    # Default to POSTing JSON unless explicitly stated otherwise
    options[:headers]['Content-Type'] = 'application/json' unless options[:headers]['Content-Type']

    do_request 'post', path, options do |request|
      request.body = body
      request.body = request.body.to_json unless options[:headers]['Content-Type'] != 'application/json'
    end
  end

  private

  def do_request (method, path, options = {})
    # For now, these are the methods we support:
    raise SierraApiClientError, "Unsupported method: #{method}" unless ['get', 'post'].include? method.downcase

    authenticate! if options[:authenticated]

    uri = URI.parse("#{@config[:base_url]}#{path}")

    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.scheme === 'https'

    # Build request headers:
    request_headers = {}
    request_headers['Content-Type'] = options[:headers]['Content-Type'] unless options.dig(:headers, 'Content-Type').nil?

    # Create HTTP::Get or HTTP::Post
    request =  Net::HTTP.const_get(method.capitalize).new(uri.path, request_headers)

    # Add bearer token header
    request['Authorization'] = "Bearer #{@access_token}" if options[:authenticated]

    # Allow caller to modify the request before we send it off:
    yield request if block_given?

    logger.debug "SierraApiClient: #{method} to Sierra api", { uri: uri, body: request.body }

    begin
      # Execute request:
      response = http.request(request)
    rescue => e
      raise SierraApiClientError.new(e), "Failed to #{method} to #{path}: #{e.message}"
    end

    logger.debug "SierraApiClient: Got Sierra api response", { code: response.code, body: response.body }

    parse_response response
  end

  def parse_response (response)
    if response.code == "401"
      # Likely an expired access-token; Wipe it for next run
      # TODO: Implement token refresh
      @access_token = nil
      raise SierraApiClientTokenError.new("Got a 401: #{response.body}")
    end
    
    SierraApiResponse.new(response)
  end

  def parse_http_options (_options)
    options = {
      authenticated: true
    }.merge _options

    options[:headers] = {
    }.merge(_options[:headers] || {})
      .transform_keys(&:to_s)

    options
  end

  # Authorizes the request.
  def authenticate!
    # NOOP if we've already authenticated
    return nil if ! @access_token.nil?

    logger.debug "SierraApiClient: Authenticating with client_id #{@config[:client_id]}"

    uri = URI.parse("#{@config[:oauth_url]}")
    request = Net::HTTP::Post.new(uri)
    request.basic_auth(@config[:client_id], @config[:client_secret])
    request.set_form_data(
      "grant_type" => "client_credentials"
    )

    req_options = {
      use_ssl: uri.scheme == "https",
      request_timeout: 500
    }

    response = Net::HTTP.start(uri.hostname, uri.port, req_options) do |http|
      http.request(request)
    end

    if response.code == '200'
      @access_token = JSON.parse(response.body)["access_token"]
    else
      nil
    end
  end

  def logger
    @logger ||= NyplLogFormatter.new(STDOUT, level: @config[:log_level])
  end
end
