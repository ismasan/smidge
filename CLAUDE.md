# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What is Smidge?

Smidge is a Ruby gem that generates HTTP client methods from OpenAPI 3.x specifications. It parses OpenAPI specs and dynamically creates client classes with methods for each API operation.

## Commands

```bash
# Run tests
rake spec
bundle exec rspec

# Install dependencies
bin/setup

# Interactive console
bin/console

# Install gem locally
bundle exec rake install
```

## Architecture

```
OpenAPI Spec → Smidge.from_openapi() → Parser.OpenAPI → Parser.BuildOperations
    → Client class (dynamic methods) → RunnableOperation → HTTPAdapter → Response
```

### Core Components

- **`Smidge` module** (`lib/smidge.rb`): Entry point. `Smidge.from_openapi(spec, http:, base_url:)` creates client classes from OpenAPI specs (URL, Hash, or file path).

- **`Smidge::Client`** (`lib/smidge/client.rb`): Base class for generated clients. Operations become instance methods. Supports class-level DSL via `operation` and `info` methods. Contains `RunnableOperation` which wraps operations with HTTP execution.

- **`Smidge::Operation`** (`lib/smidge/operation.rb`): Represents a single API endpoint. Handles parameter extraction (`path_for`, `query_for`, `payload_for`). Contains `Param` and `ParamBuilder` nested classes.

- **`Smidge::Parser`** (`lib/smidge/parser.rb`): Parses OpenAPI specs using Plumb validation. Handles `$ref` resolution, parameter extraction, and converts specs to Operation objects.

- **HTTP Adapters**: `HTTPAdapter` (Net::HTTP for real requests) and `InprocAdapter` (Rack-based for testing, requires `rack` gem and explicit `require 'smidge/inproc_adapter'`). Adapters implement `get`, `post`, `put`, `patch`, `delete`.

### Key Patterns

- Method names generated from operationId via `Smidge.to_method_name()` (camelCase → snake_case)
- Path parameters substituted into URL templates: `/users/{id}` → `/users/123`
- RubyLLM integration via `client.to_llm_tools` for LLM function calling

## Dependencies

- **Runtime**: `plumb` (>= 0.0.16) for data validation/transformation
- **Ruby**: >= 3.1.0

## Usage Patterns

```ruby
# From OpenAPI spec
client = Smidge.from_openapi('https://api.example.com/openapi.json')
client.list_users(q: 'john')

# Manual client definition
class PetsAPI < Smidge::Client
  info title: 'Pets API', version: '1.0'
  operation name: :list_pets, verb: :get, path: '/pets' do |op|
    op.param name: 'limit', type: 'integer'
  end
end

# In-process testing with Rack apps (requires rack gem)
require 'smidge/inproc_adapter'
adapter = Smidge::InprocAdapter.new(my_rack_app)
client = MyClient.new(base_url: 'http://test', http: adapter)
```
