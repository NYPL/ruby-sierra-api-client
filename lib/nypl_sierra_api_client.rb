require 'net/http'
require 'net/https'
require 'uri'
require 'nypl_log_formatter'

require_relative 'errors'
require_relative 'sierra_api_response'

class SierraApiClient
  def initialize(config = {})
    config_defaults = {
      env: {
        base_url: 'SIERRA_API_BASE_URL',
        client_id: 'SIERRA_OAUTH_ID',
        client_secret: 'SIERRA_OAUTH_SECRET',
        oauth_url: 'SIERRA_OAUTH_URL'
      },
      static: {
        log_level: 'info'
      }
    }

    @config = config_defaults[:env].map {|k,v| [k, ENV[v]]}.to_h
      .merge config_defaults[:static]
      .merge config

    config_defaults[:env].each do |key, value|
      raise SierraApiClientError.new "Missing config: neither config.#{key} nor ENV.#{value} are set" unless @config[key]
    end

    @retries = 0
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

    @uri = URI.parse("#{@config[:base_url]}#{path}")

    # Build request headers:
    request_headers = {}
    request_headers['Content-Type'] = options[:headers]['Content-Type'] unless options.dig(:headers, 'Content-Type').nil?

    # Create HTTP::Get or HTTP::Post
    request =  Net::HTTP.const_get(method.capitalize).new(@uri, request_headers)

    # Add bearer token header
    request['Authorization'] = "Bearer #{@access_token}" if options[:authenticated]

    # Allow caller to modify the request before we send it off:
    yield request if block_given?

    logger.debug "SierraApiClient: #{method} to Sierra api", { uri: @uri, body: request.body }

    response = execute request

    logger.debug "SierraApiClient: Got Sierra api response", { code: response.code, body: response.body }

    handle_response response, request
  end

  def handle_response (response, request)
    if response.code == "401"
      # Likely an expired access-token; Wipe it for next run
      # TODO: Implement token refresh
      @access_token = nil
      logger.debug "SierraApiClient: Unathorized", { code: 401, body: response.body }
      reattempt request
    end

    reset_retries if @retries > 0
    SierraApiResponse.new(response)
  end

  def execute (request)
    http = Net::HTTP.new(@uri.host, @uri.port)
    http.use_ssl = @uri.scheme === 'https'

    begin
      return http.request(request)
    rescue => e
      raise SierraApiClientError.new(e), "Failed to #{method} to #{path}: #{e.message}"
    end
  end

  def reattempt request
    raise SierraApiClientTokenError.new("Maximum retries exceeded") if @retries >= 3

    @retries += 1
    logger.debug "SierraApiClient: Refereshing oauth token for 401", { retry: @retries }

    authenticate!
    # Reset bearer token header
    request['Authorization'] = "Bearer #{@access_token}"

    response = execute request

    handle_response response, request
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

  def reset_retries
    @retries = 0
  end
end
