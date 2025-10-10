# Smidge

**WORK IN PROGRESS**

A lightweight HTTP client that automatically generates methods from OpenAPI specifications

  Key features

  1. OpenAPI spec parsing - Reads [OpenAPI 3.x](https://spec.openapis.org/oas/v3.2.0) specs from URLs, files, or hashes (lib/smidge/parser.rb:1)
  2. Dynamic client generation - Automatically creates methods for each API endpoint based on the spec's operationId (lib/smidge/client.rb:118-124)
  3. Parameter handling - Extracts and handles:

    - Path parameters (e.g., /users/{id})
    - Query parameters
    - Request body parameters (JSON)
  (lib/smidge/client.rb:38-98)
  4. HTTP adapters - Pluggable HTTP transport layer supporting both real HTTP requests and in-process adapters for testing
  5. LLM integration - Includes an example showing how to convert API endpoints into LLM tools using RubyLLM (examples/llm_chat.rb:1)

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

## Usage

```ruby
# Load API from OpenAPI spec
client = Smidge.from_openapi('https://api.example.com/openapi.json')

# Inspecting operations
op = client.get_users
# or op = client[:get_users]
op.parameters[:q].description # "Filter users by name"
op.parameters[:q].type # :string

# Call endpoints using generated operations
client.get_users.run(limit: 10) # Net::HTTP::Response, parsed #body
client.create_post(title: 'Hello', body: 'World')

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



## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and the created tag, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/ismasan/smidge.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).	
