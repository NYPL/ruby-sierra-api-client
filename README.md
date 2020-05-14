# Ruby Sierra API Client

Simple client for querying the Sierra API

## Version

> 1.0.3

## Using

1. Configure the client with Sierra API credentials
2. Make requests

### Configuration

Example configuration:

```ruby
require 'nypl_sierra_api_client'

client = SierraApiClient.new({
  base_url: "https://[fqdn]/iii/sierra-api/v5", # Defaults to ENV['SIERRA_API_BASE_URL']
  client_id: "client-id", # Defaults to ENV['SIERRA_OAUTH_ID']
  client_secret: "client-secret", # Defaults to ENV['SIERRA_OAUTH_SECRET']
  oauth_url: "https://[fqdn]/iii/sierra-api/v3/token", # Defaults to ENV['SIERRA_OAUTH_URL'],
  log_level: "debug" # Defaults to 'info'
})
```

### Requests

Example GET:

```ruby
bib_response = sierra_client.get 'bibs/12345678'
bib = bib_response.body
```

Example POST:

```ruby
check_login = sierra_client.post 'patrons/validate', { "barcode": "1234", "pin": "6789" }
valid = check_login.success?
invalid = check_login.error?
```

Note that only GET and POST are supported at writing.

### Responses

Because of the variety of HTTP status codes and "Content-Type"s returned by the Sierra REST API, the Sierra API Client makes few assumptions about the response. All calls return a `SierraApiResponse` object with the following methods:

 * `code`: HTTP status code as an Integer (e.g. `200`, `500`)
 * `success?`: True if `code` is 2** or 3**
 * `error?`: True if `code` is >= `400`
 * `body`: The returned body. If response header indicates it's JSON, it will be a `Hash`.
 * `response`: The complete [`Net::HTTPResponse`](https://ruby-doc.org/stdlib-2.7.1/libdoc/net/http/rdoc/Net/HTTPResponse.html) object for inspecting anything else you like.

In the spirit of agnostism, the client will not intentionally raise an error when it encounters an error HTTP status code. Client will only raise an error when the request could not be carried out as specified and should be retried, that is:
 - Network failure
 - Invalid token error (401)

## Contributing

This repo uses a single, versioned `master` branch.

 * Create feature branch off `master`
 * Compute next logical version and update `README.md`, `CHANGELOG.md`, & `nypl_sierra_api_client.gemspec`
 * Create PR against `master`
 * After merging the PR, git tag `master` with new version number.

### Updating gem

After merging to `master`, push the updated gem to rubygems.org:

```
gem build nypl_sierra_api_client.gemspec
gem push nypl_sierra_api_client-[version].gem
```

See [this guide](https://guides.rubygems.org/make-your-own-gem/) for additional help.

## Testing

```
bundle exec rspec
```
