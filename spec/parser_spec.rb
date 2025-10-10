# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Smidge::Parser do
  let(:openapi_spec) do
    {
      "openapi" => "3.0.0",
      "info" => {
        "title" => "Users API",
        "description" => "API for managing users",
        "version" => "0.0.1"
      },
      "servers" => [
        {
          "url" => "http://localhost:9292",
          "description" => "prod server"
        },
        {
          "url" => "https://staging.api.com",
          "description" => "Staging server"
        }
      ],
      "paths" => paths,
      "components" => components
    }
  end

  let(:paths) do
    {
      '/users' => {
        'get' => {
          'operationId' => 'users',
          'description' => 'List users',
          'parameters' => [
            {"name" => "q", "in" => "query", "description" => "search by name", "example" => "bill", "required" => false},
            {"name" => "cat", "in" => "query", "description" => "search by category", "required" => false}
          ]
        },
        'post' => {
          'description' => 'Create a user',
          'operationId' => 'create_user',
          "requestBody" => {
            "required" => true, 
            "content" => {
              "application/json" => {
                "schema" => {
                  'type' => 'object',
                  'properties' => {
                    'name' => {'type' => 'string', 'description' => 'User name'},
                    'age' => {'type' => 'integer'}
                  }
                }
              }
            }
          }
        }
      },
      '/users/{id}' => {
        'put' => {
          "description" => "Update a user",
          'operationId' => 'updateUser',
          "parameters" => [{"name" => "id", "in" => "path", "description" => nil, "required" => true, "schema" => {"type" => "string"}}],
          "requestBody" => {
            "required" => true, 
            "content" => {
              "application/json" => {
                "schema" => {
                  '$ref' => '#/components/schemas/User'
                }
              }
            }
          }
        }
      }
    }
  end

  let(:components) do
    {
      'schemas' => {
        'User' => {
          "type" => "object", 
          "properties" => {
            "name" => {"type" => "string", 'description' => 'User name' }, 
            "age" => {"type" => "integer", 'example' => 30 },
            "file" => {"type" => "string", "format" => "byte"}
          }, 
          "required" => ["name", "age"]
        }
      }
    }
  end

  it 'parses spec, resolves referenced schemas' do
    spec = Smidge::Parser::OpenAPI.parse(openapi_spec)
    update_user = spec.dig('paths', '/users/{id}', 'put')
    expect(update_user['description']).to eq 'Update a user'
    expect(update_user['parameters'].size).to eq 1
    param = update_user['parameters'].first
    expect(param['name']).to eq 'id'
    expect(param['in']).to eq 'path'
    expect(param['required']).to eq true
    expect(param['schema']['type']).to eq 'string'

    req_body_schema = update_user.dig('requestBody', 'content', 'application/json', 'schema')
    expect(req_body_schema['type']).to eq 'object'
    expect(req_body_schema['properties'].size).to eq 3
    expect(req_body_schema['required']).to eq %w[name age]
    expect(req_body_schema['properties']['name']['type']).to eq 'string'
    expect(req_body_schema['properties']['name']['description']).to eq 'User name'
    expect(req_body_schema['properties']['age']['type']).to eq 'integer'
    expect(req_body_schema['properties']['age']['example']).to eq 30
    expect(req_body_schema['properties']['file']['type']).to eq 'string'
    expect(req_body_schema['properties']['file']['format']).to eq 'byte'

    create_user = spec.dig('paths', '/users', 'post')
    expect(create_user['description']).to eq 'Create a user'
    req_body_schema = create_user.dig('requestBody', 'content', 'application/json', 'schema')
    expect(req_body_schema['type']).to eq 'object'
    expect(req_body_schema['properties'].size).to eq 2
    expect(req_body_schema['required']).to eq []
    expect(req_body_schema['properties']['name']['type']).to eq 'string'
    expect(req_body_schema['properties']['name']['description']).to eq 'User name'
  end

  describe Smidge::Parser::OpenAPIToOperations do
    it 'parses an OpenAPI spec into a list of Smidge::Operation' do
      ops = Smidge::Parser::OpenAPIToOperations.parse(openapi_spec)
      expect(ops.map(&:class).uniq).to eq([Smidge::Operation])
      expect(ops.map(&:rel_name)).to eq %i[users create_user update_user]
      expect(ops.first.params.map(&:name)).to eq %i[q cat]
      expect(ops.first.params.map(&:required)).to eq [false, false]
      expect(ops.first.params.map(&:description)).to eq ['search by name (eg bill)', 'search by category']

      expect(ops.last.params.map(&:name)).to eq %i[id name age file]
      expect(ops.last.params.map(&:required)).to eq [true, true, true, false]
    end
  end
end
