require 'spec_helper'
require 'webmock/rspec'

describe SierraApiClient do
  before(:each) do
    ENV['SIERRA_API_BASE_URL'] = 'https://example.com/iii/'
    ENV['SIERRA_OAUTH_ID'] = Base64.strict_encode64 'fake-client'
    ENV['SIERRA_OAUTH_SECRET'] = Base64.strict_encode64 'fake-secret'
    ENV['SIERRA_OAUTH_URL'] = 'https://example.com/token'

    stub_request(:post, "#{ENV['SIERRA_OAUTH_URL']}")
      .to_return(status: 200, body: '{ "access_token": "fake-access-token" }')
    stub_request(:get, "#{ENV['SIERRA_API_BASE_URL']}patrons/12345")
      .to_return({
        status: 200,
        headers: { 'Content-Type' => 'application/json;charset=UTF-8' }
      })
  end

  describe :config do
    it "should throw error if api base url unset" do
      ENV['SIERRA_API_BASE_URL'] = nil
      expect { SierraApiClient.new }.to raise_error(SierraApiClientError)
    end

    it "should throw error if client id unset" do
      ENV['SIERRA_OAUTH_ID'] = nil
      expect { SierraApiClient.new }.to raise_error(SierraApiClientError)
    end

    it "should throw error if client secret unset" do
      ENV['SIERRA_OAUTH_SECRET'] = nil
      expect { SierraApiClient.new }.to raise_error(SierraApiClientError)
    end

    it "should throw error if oauth url unset" do
      ENV['SIERRA_OAUTH_URL'] = nil
      expect { SierraApiClient.new }.to raise_error(SierraApiClientError)
    end

    it "should allow configuration via constructor" do
      ENV['SIERRA_API_BASE_URL'] = nil
      ENV['SIERRA_OAUTH_ID'] = nil
      ENV['SIERRA_OAUTH_SECRET'] = nil
      ENV['SIERRA_OAUTH_URL'] = nil

      config = SierraApiClient.new({
        base_url: 'https://example.com/iii/',
        client_id: 'client-id',
        client_secret: 'client-secret',
        oauth_url: 'https://example.com/token'
      }).instance_variable_get(:@config)

      expect(config).to be_a(Hash)
      expect(config[:base_url]).to eq('https://example.com/iii/')
      expect(config[:client_id]).to eq('client-id')
    end

    it "should prefer constructor config over ENV variables" do
      client = SierraApiClient.new({
        client_id: 'client-id-via-constructor-config'
      })
      expect(client.instance_variable_get(:@config)).to be_a(Hash)
      expect(client.instance_variable_get(:@config)[:client_id]).to eq('client-id-via-constructor-config')
    end

    it "should set default log_level to 'info'" do
      client = SierraApiClient.new
      expect(client.instance_variable_get(:@config)).to be_a(Hash)
      expect(client.instance_variable_get(:@config)[:log_level]).to eq('info')
    end

    it "should allow log_level override via constructor (only)" do
      ENV['LOG_LEVEL'] = 'debug'
      client = SierraApiClient.new
      expect(client.instance_variable_get(:@config)).to be_a(Hash)
      expect(client.instance_variable_get(:@config)[:log_level]).to eq('info')

      client = SierraApiClient.new(log_level: 'debug')
      expect(client.instance_variable_get(:@config)).to be_a(Hash)
      expect(client.instance_variable_get(:@config)[:log_level]).to eq('debug')
    end
  end

  describe :parse_http_options do
    it "should assume common defaults" do
      options = SierraApiClient.new.send :parse_http_options, {}

      expect(options[:authenticated]).to eq(true)
      expect(options[:headers]).to be_a(Hash)
      expect(options[:headers].keys.size).to eq(0)
    end

    it "should allow authentication override" do
      options = SierraApiClient.new.send :parse_http_options, { authenticated: false }

      expect(options[:authenticated]).to eq(false)
    end

    it "should allow custom Content-Type" do
      options = SierraApiClient.new.send :parse_http_options, { headers: { 'Content-Type' => 'text/plain' } }

      expect(options[:headers]).to be_a(Hash)
      expect(options[:headers]['Content-Type']).to be_a(String)
      expect(options[:headers]['Content-Type']).to eq('text/plain')
    end

    it "should allow extra header" do
      options = SierraApiClient.new.send :parse_http_options, { headers: { 'X-My-Header': 'header value' } }

      expect(options[:authenticated]).to eq(true)
      expect(options[:headers]).to be_a(Hash)
      expect(options[:headers]['X-My-Header']).to eq('header value')
    end
  end

  describe :authentication do

    it "should authenticate by default" do
      client = SierraApiClient.new

      # Verify no access token:
      expect(client.instance_variable_get(:@access_token)).to be_nil

      # Call an endpoint with authentication:
      expect(client.get('patrons/12345')).to be_a(Object)

      # Verify access_token retrieved:
      expect(client.instance_variable_get(:@access_token)).to be_a(String)
      expect(client.instance_variable_get(:@access_token)).to eq('fake-access-token')
    end

    it "should authenticate when calling with :authenticated => true" do
      client = SierraApiClient.new

      # Verify no access token:
      expect(client.instance_variable_get(:@access_token)).to be_nil

      # Call an endpoint with authentication:
      expect(client.get('patrons/12345', authenticated: true)).to be_a(Object)

      # Verify access_token retrieved:
      expect(client.instance_variable_get(:@access_token)).to be_a(String)
      expect(client.instance_variable_get(:@access_token)).to eq('fake-access-token')
    end

    it "should NOT authenticate when calling with :authenticated => false" do
      client = SierraApiClient.new

      # Verify no access token:
      expect(client.instance_variable_get(:@access_token)).to be_nil

      # Call an endpoint without authentication:
      expect(client.get('patrons/12345', authenticated: false)).to be_a(Object)

      # Verify access_token retrieved:
      expect(client.instance_variable_get(:@access_token)).to be_nil
    end
  end

  describe :do_request do
    it "should throw if invalid method" do
      expect { SierraApiClient.new.send :do_request, 'patch', 'some-path' }.to raise_error(SierraApiClientError)
    end

    it "should perform get" do
      stub_request(:get, "#{ENV['SIERRA_API_BASE_URL']}some-path")
        .to_return({
          status: 200,
          body: '{ "foo": "bar" }',
          headers: { 'Content-Type' => 'application/json;charset=UTF-8' }
        })

      resp = SierraApiClient.new.send :do_request, 'get', 'some-path'
      expect(resp).to be_a(SierraApiResponse)
      expect(resp.body).to be_a(Hash)
      expect(resp.body['foo']).to eq('bar')
    end

  end

  describe :responses do
    it "should auto parse JSON if Content-Type is json and 200 response" do
      stub_request(:get, "#{ENV['SIERRA_API_BASE_URL']}some-path")
        .to_return({
          status: 200,
          body: '{ "foo": "bar" }',
          headers: { 'Content-Type' => 'application/json;charset=UTF-8' }
        })

      resp = SierraApiClient.new.get('some-path')
      expect(resp).to be_a(SierraApiResponse)
      expect(resp.body).to be_a(Hash)
      expect(resp.body['foo']).to eq('bar')
    end

    it "should not auto parse JSON if response Content-Type is other than application/json" do
      stub_request(:get, "#{ENV['SIERRA_API_BASE_URL']}some-path")
        .to_return({
          status: 404,
          body: '{ "foo": "bar" }',
          headers: {
            'Content-Type' => 'text/html; charset=UTF-8'
          }
        })

      resp = SierraApiClient.new.get('some-path')
      expect(resp).to be_a(SierraApiResponse)
      expect(resp.body).to be_a(String)
      expect(JSON.parse(resp.body)).to be_a(Hash)
      expect(JSON.parse(resp.body)['foo']).to eq('bar')
    end

    it "should throw SierraApiClientError if response is not valid json" do
      stub_request(:get, "#{ENV['SIERRA_API_BASE_URL']}some-path")
        .to_return({
          status: 200,
          body: '{ ""mangled json }',
          headers: {
            'Content-Type' => 'application/json;charset=UTF-8'
          }
        })
      expect { SierraApiClient.new.get('some-path').body }.to raise_error(SierraApiResponseError)
    end

    it "should not throw errors for 500" do
      stub_request(:get, "#{ENV['SIERRA_API_BASE_URL']}some-path").to_return(status: 500, body: '' )

      resp = SierraApiClient.new.get('some-path')
      expect(resp).to be_a(SierraApiResponse)
      expect(resp.code).to eq(500)
    end
  end

  describe :refresh_oauth do
    before do
      stub_request(:get, "#{ENV['SIERRA_API_BASE_URL']}one-reattempt").to_return(
        { status: 401, body: '{ "foo": "bar1" }' },
        { status: 200, body: '{ "foo": "bar1" }' },
      )

      stub_request(:get, "#{ENV['SIERRA_API_BASE_URL']}maximum-attempts-path").to_return(status: 401, body: '{ "foo": "bar1" }')

      stub_request(:post, "#{ENV['SIERRA_OAUTH_URL']}")
        .to_return(
          { status: 200, body: '{ "access_token": "fake-access-token" }' },
          { status: 200, body: '{ "access_token": "second-fake-access-token" }' },
        )
    end

    it "should refresh oauth token for 401" do
      client = SierraApiClient.new
      first_token = client.instance_variable_get(:@access_token)

      resp = client.get('one-reattempt')
      second_token = client.instance_variable_get(:@access_token)

      expect(first_token).not_to eq(second_token)
      expect(client.instance_variable_get(:@retries)).to eq(0)
      expect(resp).to be_a(SierraApiResponse)
      expect(resp.code).to eq(200)
    end

    it "should throw error once maximum retries attempted" do
      client = SierraApiClient.new
      expect { client.get('maximum-attempts-path') }.to raise_error(SierraApiClientTokenError)
      assert_requested(
        :get,
        "#{ENV['SIERRA_API_BASE_URL']}maximum-attempts-path",
        times: 4
      )
      expect(client.instance_variable_get(:@retries)).to eq(0)
    end
  end
end
