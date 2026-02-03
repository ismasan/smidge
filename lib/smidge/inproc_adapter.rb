# frozen_string_literal: true

require 'rack'

module Smidge
  # In-process HTTP adapter for testing Smidge clients against Rack applications
  #
  # This adapter sends requests directly to a Rack app without making real HTTP
  # requests, making it ideal for testing. It implements the same interface as
  # {HTTPAdapter}, so clients work identically with either adapter.
  #
  # @example Basic usage
  #   require 'smidge/inproc_adapter'
  #
  #   app = MyRackApp.new
  #   adapter = Smidge::InprocAdapter.new(app)
  #   client = MyClient.new(base_url: 'http://test', http: adapter)
  #   response = client.list_users
  #
  # @example In RSpec
  #   let(:adapter) { Smidge::InprocAdapter.new(MyRackApp.new) }
  #   let(:client) { MyClient.new(base_url: 'http://test', http: adapter) }
  #
  #   it 'lists users' do
  #     expect(client.list_users.code).to eq '200'
  #   end
  #
  # @note Requires the `rack` gem as a dependency
  #
  class InprocAdapter
    # Initialize a new in-process adapter
    #
    # @param app [#call] A Rack-compatible application
    def initialize(app)
      @app = app
    end

    # Send a GET request
    #
    # @param url [String] The URL to request
    # @param body [Hash, String, nil] Optional request body
    # @param headers [Hash, nil] Optional HTTP headers
    # @param symbolize_names [Boolean] Whether to symbolize JSON response keys
    # @return [Net::HTTPResponse] The response object with parsed body
    def get(url, body: nil, headers: nil, symbolize_names: true)
      request(:get, url, body, headers, symbolize_names:)
    end

    # Send a PUT request
    #
    # @param url [String] The URL to request
    # @param body [Hash, String, nil] Optional request body (auto-serialized to JSON if Hash)
    # @param headers [Hash, nil] Optional HTTP headers
    # @return [Net::HTTPResponse] The response object with parsed body
    def put(url, body: nil, headers: nil)
      request(:put, url, body, headers)
    end

    # Send a POST request
    #
    # @param url [String] The URL to request
    # @param body [Hash, String, nil] Optional request body (auto-serialized to JSON if Hash)
    # @param headers [Hash, nil] Optional HTTP headers
    # @return [Net::HTTPResponse] The response object with parsed body
    def post(url, body: nil, headers: nil)
      request(:post, url, body, headers)
    end

    # Send a PATCH request
    #
    # @param url [String] The URL to request
    # @param body [Hash, String, nil] Optional request body (auto-serialized to JSON if Hash)
    # @param headers [Hash, nil] Optional HTTP headers
    # @return [Net::HTTPResponse] The response object with parsed body
    def patch(url, body: nil, headers: nil)
      request(:patch, url, body, headers)
    end

    # Send a DELETE request
    #
    # @param url [String] The URL to request
    # @param body [Hash, String, nil] Optional request body
    # @param headers [Hash, nil] Optional HTTP headers
    # @return [Net::HTTPResponse] The response object with parsed body
    def delete(url, body: nil, headers: nil)
      request(:delete, url, body, headers)
    end

    # @api private
    JSON_MIME = 'application/json'

    # Execute an HTTP request against the Rack app
    #
    # @param verb [Symbol] The HTTP method (:get, :post, :put, :patch, :delete)
    # @param url [String] The URL to request
    # @param body [Hash, String, nil] Optional request body
    # @param headers [Hash, nil] Optional HTTP headers
    # @param symbolize_names [Boolean] Whether to symbolize JSON response keys
    # @return [Net::HTTPResponse] The response object with parsed body
    def request(verb, url, body, headers, symbolize_names: true)
      uri = URI(url)
      body = body ? StringIO.new(body.is_a?(Hash) ? JSON.dump(body) : body.to_s) : nil
      env = Rack::MockRequest.env_for(
        uri.to_s,
        rack_headers(headers).merge({
          'REQUEST_METHOD' => verb.to_s.upcase,
          'CONTENT_TYPE' => JSON_MIME,
          'HTTP_ACCEPT' => JSON_MIME,
          Rack::RACK_INPUT => body
        })
      )

      status, resp_headers, resp_body = @app.call(env)
      rresponse = Rack::Response.new(resp_body, status, resp_headers)
      resp_body = rresponse.body.each_with_object(+'') { |part, memo| memo << part }

      if rresponse.content_type == JSON_MIME && resp_body && !resp_body.empty?
        resp_body = JSON.parse(resp_body, symbolize_names:)
      end

      response = Net::HTTPResponse::CODE_TO_OBJ[status.to_s].new('1.1', status.to_s, '')
      rresponse.headers.each { |k, v| response[k] = v }
      response.instance_variable_set(:@read, true)
      response.body = resp_body
      response
    end

    private

    # Convert HTTP headers to Rack's expected format
    #
    # @param headers [Hash, nil] HTTP headers (e.g., {'Authorization' => 'Bearer token'})
    # @return [Hash] Headers in Rack format (e.g., {'HTTP_AUTHORIZATION' => 'Bearer token'})
    def rack_headers(headers)
      return {} unless headers

      headers.each_with_object({}) do |(key, value), hash|
        rack_key = case key
        when 'Content-Type' then 'CONTENT_TYPE'
        when 'Content-Length' then 'CONTENT_LENGTH'
        else
          "HTTP_#{key.upcase.tr('-', '_')}"
        end
        hash[rack_key] = value
      end
    end
  end
end
