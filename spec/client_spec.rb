# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Smidge::Client do
  subject(:client) { described_class.new(openapi_spec, http:) }

  let(:http) { double('http') }
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
          "url" => "http://localhost:4567",
          "description" => "prod server"
        },
        {
          "url" => "http://localhost:9292",
          "description" => "Current server"
        }
      ],
      "paths" =>
        {"/users" =>
          {"get" =>
            {"summary" => "users",
            "operationId" => "users",
            "description" => "List users",
            "parameters" => [
              {"name" => "q", "in" => "query", "description" => "search by name", "example" => "bill", "required" => false},
              {"name" => "cat", "in" => "query", "description" => "search by category", "required" => false}
            ],
          }
        },
        "/users/{id}" =>
          {"put" =>
            {"summary" => "update_user",
            "operationId" => "update_user",
            "description" => "Update a user",
            "parameters" => [{"name" => "id", "in" => "path", "description" => nil, "required" => true, "schema" => {"type" => "string"}}],
            "requestBody" => {
              "required" => true, 
                "content" => {
                  "application/json" => {
                    "schema" => {
                      "type" => "object", 
                      "properties" => {
                        "name" => {"type" => "string"}, 
                        "age" => {"type" => "integer"}, 
                        "file" => {"type" => "string", "format" => "byte"}
                      }, 
                    "required" => ["name", "age", "file"]
                  }
                }
              }
            }
          }
        }
      }
    }
  end

  specify 'bootstrap client from OpenAPI spec' do
    expect(client.base_url).to eq(URI('http://localhost:9292'))
    expect(client.respond_to?(:update_user)).to be true
    response = double(
      'Response', 
      body: {ok: true, id: 123, name: 'John'},
      status: 200, 
      content_type: 'application/json'
    )
    expect(http).to receive(:put)
      .with(
        'http://localhost:9292/users/10', 
        body: { name: 'John', age: 30, file: 'filedata' }, 
        headers: { 
          'Content-Type' => 'application/json', 
          'Accept' => 'application/json',
          'User-Agent' => "Smidge::Client/#{Smidge::VERSION} (Ruby/#{RUBY_VERSION})"
        }
      )
      .and_return(response)

    resp = client.update_user(id: 10, name: 'John', age: 30, file: 'filedata')
    expect(resp.body[:ok]).to be true
  end

  specify 'fail loudly if Hash is an incomplete OpenAPI spec' do
    expect {
      described_class.new({info: {}}, http:)
    }.to raise_error(Smidge::InvalidSpecError)
  end

  describe 'Smidge.from_openapi' do
    describe 'with a #read interface' do
      it 'assumes the content is JSON, and parses it' do
        json = JSON.dump(openapi_spec)
        reader = StringIO.new(json)
        client = Smidge.from_openapi(reader, http:)
        expect(client).to be_a(Smidge::Client)
        expect(client._operations.values.map(&:rel_name)).to include(:users, :update_user)
      end
    end

    describe 'with a Hash' do
      it 'uses the hash as a spec' do
        client = Smidge.from_openapi(openapi_spec, http:)
        expect(client).to be_a(Smidge::Client)
        expect(client._operations.values.map(&:rel_name)).to include(:users, :update_user)
      end
    end

    describe 'with url' do
      it 'uses HTTP adapter to fetch the spec' do
        response = instance_double(
          Net::HTTPResponse, 
          body: openapi_spec,
          code: 200, 
          content_type: 'application/json'
        )

        expect(http).to receive(:get)
          .with(
            'https://api.com/openapi.json',
            headers: { 
              'Content-Type' => 'application/json', 
              'Accept' => 'application/json',
              'User-Agent' => "Smidge::Client/#{Smidge::VERSION} (Ruby/#{RUBY_VERSION})"
            },
            symbolize_names: false
          )
          .and_return(response)

        client = Smidge.from_openapi('https://api.com/openapi.json', http:)
        expect(client).to be_a(Smidge::Client)
        expect(client._operations[:users].rel_name).to eq(:users)
        expect(client._operations[:users].verb).to eq(:get)
        expect(client._operations[:users].description).to eq('List users')
        client._operations[:users].query_params.first.tap do |p|
          expect(p.name).to eq(:q)
          expect(p.description).to eq('search by name')
          expect(p.example).to eq('bill')
          expect(p.description_with_example).to eq('search by name (e.g. bill)')
        end
      end

      it 'raises a useful exception if the response is invalid' do
        response = instance_double(
          Net::HTTPResponse, 
          code: 404, 
          content_type: 'application/json'
        )

        expect(http).to receive(:get).and_return(response)

        expect {
          Smidge.from_openapi('https://api.com/openapi.json', http:)
        }.to raise_error(Smidge::MissingHTTPSpecError)
      end
    end
  end
end
