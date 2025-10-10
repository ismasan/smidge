# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Smidge::Client do
  subject(:client) { Smidge.from_openapi(openapi_spec, http:) }

  let(:http) { double('http') }
  let(:openapi_spec) do
    {
      "openapi" => "3.0.0",
      "info" => {
        "title" => "Users API",
        "description" => "API for managing users",
        "version" => "0.0.1"
      },
      'servers' => servers,
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
                        "name" => {"type" => "string", 'description' => 'User name', 'example' => 'Joe' }, 
                        "age" => {"type" => "integer", 'example' => 30 },
                        "file" => {"type" => "string", "format" => "byte"}
                      }, 
                    "required" => ["name", "age", 'file']
                  }
                }
              }
            }
          }
        }
      }
    }
  end

  let(:servers) do
    [
      {
        "url" => "http://localhost:9292",
        "description" => "prod server"
      },
      {
        "url" => "https://staging.api.com",
        "description" => "Staging server"
      }
    ]
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

    op = client[:update_user]
    expect(op.name).to eq(:update_user)
    expect(op.description).to eq('Update a user')
    expect(op.parameters[:name].description).to eq('User name (eg Joe)')
    expect(op.parameters[:name].name).to eq(:name)
    expect(op.parameters[:name].in).to eq('body')
    expect(op.parameters[:name].required).to be(true)
    expect(op.parameters[:name].type).to eq(:string)

    resp = op.run(id: 10, name: 'John', age: 30, file: 'filedata')
    expect(resp.body[:ok]).to be true
  end

  specify '#to_llm_tools' do
    response = double(
      'Response', 
      body: {ok: true, id: 123, name: 'John'},
      status: 200, 
      content_type: 'application/json'
    )
    allow(http).to receive(:put).and_return(response)

    tools = client.to_llm_tools
    expect(tools.map(&:name)).to eq %i[users update_user]
    expect(tools.map(&:description)).to eq ['List users', 'Update a user']
    expect(tools.last.parameters.values.map(&:name)).to eq %i[id name age file]
    expect(tools.last.parameters.values.map(&:description)).to eq ['', 'User name (eg Joe)', ' (eg 30)', '']
    data = tools.last.call(id: 10, name: 'John', age: 30)
    expect(data).to eq(ok: true, id: 123, name: 'John')
  end

  specify 'fail loudly if Hash is an incomplete OpenAPI spec' do
    expect {
      Smidge.from_openapi({info: {}}, http:, base_url: 'http://localhost:9292')
    }.to raise_error(Plumb::ParseError)
  end

  describe 'Smidge.from_openapi' do
    describe 'with a #read interface' do
      it 'assumes the content is JSON, and parses it' do
        json = JSON.dump(openapi_spec)
        reader = StringIO.new(json)
        client = Smidge.from_openapi(reader, http:)
        expect(client).to be_a(Smidge::Client)
        expect(client._operations.values.map(&:name)).to include(:users, :update_user)
      end
    end

    describe 'with a Hash' do
      it 'uses the hash as a spec' do
        client = Smidge.from_openapi(openapi_spec, http:)
        expect(client).to be_a(Smidge::Client)
        expect(client._operations.values.map(&:name)).to include(:users, :update_user)
      end
    end

    describe 'with url' do
      let(:response) do
        instance_double(
          Net::HTTPResponse, 
          body: openapi_spec,
          code: 200, 
          content_type: 'application/json'
        )
      end

      before do
        allow(http).to receive(:get)
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
      end

      it 'uses HTTP adapter to fetch the spec' do
        client = Smidge.from_openapi('https://api.com/openapi.json', http:)
        expect(client).to be_a(Smidge::Client)
        expect(client._operations[:users].name).to eq(:users)
        expect(client._operations[:users].verb).to eq(:get)
        expect(client._operations[:users].description).to eq('List users')
        client._operations[:users].parameters.values.first.tap do |p|
          expect(p.name).to eq(:q)
          expect(p.description).to eq('search by name (eg bill)')
          expect(p.example).to eq('bill')
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

      describe 'when no base_url given, and spec does not have servers info' do
        let(:servers) { [] }

        it 'uses spec URL base as base_url' do
          client = Smidge.from_openapi('https://api.com/openapi.json', http:)
          expect(client.base_url.to_s).to eq('https://api.com')
        end
      end
    end

    describe 'issuing requests' do
      it 'delegates to the HTTP adapter' do
        client = Smidge.from_openapi(openapi_spec, http:)

        now = Time.now
        response = instance_double(
          Net::HTTPResponse, 
          body: { name: 'Joe', age: 40, updated_at: now },
          code: 200, 
          content_type: 'application/json'
        )

        expect(http).to receive(:put)
          .with(
            'http://localhost:9292/users/1',
            headers: { 
              'Content-Type' => 'application/json', 
              'Accept' => 'application/json',
              'User-Agent' => "Smidge::Client/#{Smidge::VERSION} (Ruby/#{RUBY_VERSION})"
            },
            body: { name: 'Joe', age: 40 }
          )
          .and_return(response)

        resp = client.update_user(id: 1, name: 'Joe', age: 40)
        expect(resp.code).to eq(200)
        expect(resp.body[:name]).to eq('Joe')
        expect(resp.body[:updated_at]).to eq(now)
      end
    end
  end
end
