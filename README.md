# Smidge

**WORK IN PROGRESS**

A lightweight HTTP client that automatically generates methods from OpenAPI specifications

  Key features

  1. OpenAPI spec parsing - Reads [OpenAPI 3.x](https://spec.openapis.org/oas/v3.2.0) specs from URLs, files, or hashes.
  2. Dynamic client generation - Automatically creates methods for each API endpoint based on the spec's operationId
  3. Parameter handling - Extracts and handles:

    - Path parameters (e.g., /users/{id})
    - Query parameters
    - Request body parameters (JSON)
  4. HTTP adapters - Pluggable HTTP transport layer supporting both real HTTP requests and in-process adapters for testing
  5. LLM integration - Includes an example showing how to convert API endpoints into LLM tools using RubyLLM (`examples/llm_chat.rb`)

## Usage

```ruby
# Load API from OpenAPI spec
client = Smidge.from_openapi('https://api.example.com/openapi.json')

# Calling operations as methods
resp = client.get_users(q: 'b') # Net::HTTP::Response, parsed #body
resp.body # [{name: 'Bill'}, {name: 'Bob'}]

client.create_post(title: 'Hello', body: 'World')

# Inspecting operations
op = client[:get_users]
op.parameters[:q].description # "Filter users by name"
op.parameters[:q].type # :string
# can still be called
resp = op.run(q: 'b')


# List all operations
client._operations.values.each do |op|
  p [op.name, op.parameters]
end
```

The gem uses [Plumb](https://github.com/ismasan/plumb) for data validation and transformation. It's designed to make consuming APIs easier by eliminating boilerplate HTTP client code, and to use and test APIS that expose OpenAPI specs.

Any OpenAPI 3.0 spec will do, but I'm also working on [Steppe](https://github.com/ismasan/steppe), a Ruby toolkit for building REST APIs that generate OpenAPI specs automatically.

### Using with RubyLLM

Smidge turns operations in the OpenAPI spec into tools objects that are compatible with [RubyLLM tools](https://rubyllm.com/tools/)


```ruby
# include RubyLLM in your Gemfile
require 'ruby_llm'

# configure RubyLLM with your provider's credentials
RubyLLM.configure do |config|
  config.openai_api_key = ENV.fetch('OPENAI_API_KEY')
end

# Load API from OpenAPI spec
client = Smidge.from_openapi('https://some.wheather.api/openapi.json')

# turn OpenAPI operations into RubyLLM-compatible tools
tools = CLIENT.to_llm_tools

# register tools with RubyLLM
chat = RubyLLM.chat.with_tools(*tools)

# chat with your API!
response = chat.ask "What's the weather like in London tomorrow?"
puts response.content
```

### Manual definition

```ruby
class PetsClient < Smidge::Client
  info title: 'pets API client'

  operation name: :list_pets, verb: :get, path: '/pets', description: 'list' do |op|
    op.param name: 'q', type: 'string', required: true
    op.param name: 'id', type: 'string', example: '123'
  end
end

client = PetsClient.new
# or pass an HTTP client
# client = PetsClient.new(http: MyHTTP.new)
resp = client.list(q: 'cats') # #<Net::HTTPOK 200 OK readbody=true>
resp.body # => [{name: 'Tiger', ...}]
```

### Testing with InprocAdapter

Smidge includes an `InprocAdapter` that sends requests to an in-memory Rack application instead of making real HTTP requests. This is useful for testing your client code against a local Rack app (Sinatra, Rails, Roda, etc.) without network overhead.

The adapter requires `rack` as a dependency. Add it to your Gemfile:

```ruby
gem 'rack'
```

Then require the adapter explicitly:

```ruby
require 'smidge'
require 'smidge/inproc_adapter'

# Your Rack application
my_rack_app = MyApp.new

# Create the in-process adapter
adapter = Smidge::InprocAdapter.new(my_rack_app)

# Use with from_openapi
client = Smidge.from_openapi(
  'path/to/openapi.json',
  http: adapter,
  base_url: 'http://test'  # URL doesn't matter, requests go to your Rack app
)

# Or with a custom client class (see "Manual definition" above)
client = PetsClient.new(base_url: 'http://test', http: adapter)

# Requests are sent directly to your Rack app, no network calls
response = client.list_pets(q: 'cats')
```

In RSpec:

```ruby
require 'smidge/inproc_adapter'

RSpec.describe 'API Client' do
  let(:app) { MyRackApp.new }
  let(:adapter) { Smidge::InprocAdapter.new(app) }
  let(:client) { PetsClient.new(base_url: 'http://test', http: adapter) }

  it 'lists pets' do
    response = client.list_pets(q: 'cats')
    expect(response.code).to eq '200'
    expect(response.body).to include(:name)
  end
end
```

The adapter handles JSON serialization/parsing automatically and returns `Net::HTTPResponse` objects, so your client code works identically whether using real HTTP or in-process testing.

## Installation

TODO: Replace `UPDATE_WITH_YOUR_GEM_NAME_IMMEDIATELY_AFTER_RELEASE_TO_RUBYGEMS_ORG` with your gem name right after releasing it to RubyGems.org. Please do not do it earlier due to security reasons. Alternatively, replace this section with instructions to install your gem from git if you don't plan to release to RubyGems.org.

Install the gem and add to the application's Gemfile by executing:

```bash
bundle add UPDATE_WITH_YOUR_GEM_NAME_IMMEDIATELY_AFTER_RELEASE_TO_RUBYGEMS_ORG
```

If bundler is not being used to manage dependencies, install the gem by executing:

```bash
gem install UPDATE_WITH_YOUR_GEM_NAME_IMMEDIATELY_AFTER_RELEASE_TO_RUBYGEMS_ORG
```


## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and the created tag, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/ismasan/smidge.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).	
