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

    @config = config_defaults[:env].map {|k,v| [k, ENV[k]]}.to_h
      .merge config_defaults[:static]
      .merge config

    config_defaults[:env].each do |key, value|
      raise SierraApiClient.new "Missing config: neither config.#{key} nor ENV.#{value} are set" unless @config[key]
    end
  end

  def get (path, options = {})
    options = parse_http_options options

    authenticate! if options[:authenticated]

    uri = URI.parse("#{@config[:base_url]}#{path}")

    logger.debug "SierraApiClient: Getting from Sierra api", { uri: uri }

    begin
      request = Net::HTTP::Get.new(uri)

      # Add bearer token header
      request["Authorization"] = "Bearer #{@access_token}" if options[:authenticated]

      # Execute request:
      response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme === 'https') do |http|
        http.request(request)
      end
    rescue => e
      raise SierraApiClientError.new(e), "Failed to GET #{path}: #{e.message}"
    end

    logger.debug "SierraApiClient: Got Sierra api response", { code: response.code, body: response.body }

    parse_response response
  end


  def post (path, body, options = {})
    options = parse_http_options options

    # Default to POSTing JSON unless explicitly stated otherwise
    options[:headers]['Content-Type'] = 'application/json' unless options[:headers]['Content-Type']

    authenticate! if options[:authenticated]

    uri = URI.parse("#{@config[:base_url]}#{path}")

    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.scheme === 'https'

    begin
      request = Net::HTTP::Post.new(uri.path, 'Content-Type' => options[:headers]['Content-Type'])
      request.body = body
      request.body = request.body.to_json unless options[:headers]['Content-Type'] != 'application/json'

      logger.debug "SierraApiClient: Posting to Sierra api", { uri: uri, body: body }

      # Add bearer token header
      request['Authorization'] = "Bearer #{@access_token}" if options[:authenticated]

      # Execute request:
      response = http.request(request)
    rescue => e
      raise SierraApiClientError.new(e), "Failed to POST to #{path}: #{e.message}"
    end

    logger.debug "SierraApiClient: Got Sierra api response", { code: response.code, body: response.body }

    parse_response response
  end

  private

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
