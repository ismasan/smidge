# frozen_string_literal: true

require 'uri'
require "json"
require "stringio"
require 'smidge/http_adapter'

module Smidge
  # Client for making HTTP requests to an API based on OpenAPI specifications
  #
  # @example Creating a client
  #   client = Smidge::Client.new(operations, base_url: 'https://api.example.com')
  #   client.list_pets.run(limit: 10)
  #
  class Client
    REQUEST_HEADERS = {
      'Content-Type' => 'application/json',
      'Accept' => 'application/json',
      'User-Agent' => "Smidge::Client/#{Smidge::VERSION} (Ruby/#{RUBY_VERSION})"
    }.freeze

    class << self
      def inherited(child)
        super
        child.info(self.info.dup)
        self.operations.each do |k, op|
          child.operation[k] = op
        end
      end

      def to_s = name

      def info(i = nil)
        if i
          @info = i
        else
          @info
        end
      end

      def operations
        @operations ||= {}
      end

      def operation(op, &)
        op = case op
        when Hash
          Operation.build(op, &)
        when Operation
          op
        end

        operations[op.name] = op

        define_method(op.name) do |**kargs|
          self[op.name].run(kargs)
        end

        self
      end
    end

    # @!attribute [r] base_url
    #   @return [URI] The base URL for API requests
    # @!attribute [r] _operations
    #   @return [Hash<Symbol, RunnableOperation>] Hash of available operations
    # @!attribute [r] _info
    #   @return [Hash] API metadata information
    attr_reader :base_url

    # Initialize a new API client
    #
    # @param operations [Array<Smidge::Operation>] Array of API operations
    # @param base_url [String] The base URL for the API
    # @param info [Hash] Optional API metadata (title, version, etc.)
    # @param http [HTTPAdapter] HTTP adapter for making requests
    # @param headers [Hash] Optional custom headers to send with every request
    def initialize(base_url:, http: HTTPAdapter.new, headers: {})
      @base_url = Plumb::Types::Forms::URI::HTTP.parse(base_url)
      @_http = http
      @_headers = headers
    end

    # Returns a new client instance with additional headers
    #
    # @param headers [Hash] Headers to add to requests
    # @return [Client] A new client instance with the merged headers
    # @example
    #   authenticated_client = client.with_headers('Authorization' => 'Bearer token123')
    #   authenticated_client.list_pets(limit: 10)
    def with_headers(headers)
      self.class.new(base_url: base_url, http: _http, headers: _headers.merge(headers))
    end

    def _operations = self.class.operations

    # Access an operation by name
    #
    # @param name [String, Symbol] The operation name
    # @return [RunnableOperation, nil] The operation, or nil if not found
    # @example
    #   client[:list_pets].run(limit: 10)
    def [](name)
      op = self.class.operations.fetch(name.to_sym)
      RunnableOperation.new(op, base_url, _http, _headers)
    end

    # Returns a string representation of the client
    #
    # @return [String] A human-readable representation including base URL, API info, and operation count
    def inspect = %(<#{self.class}:#{object_id} #{base_url} "#{self.class.info['title']}"/#{self.class.info['version']} [#{self.class.operations.size} operations]>)

    # Returns all operations as an array for use with RubyLLM
    #
    # @return [Array<RunnableOperation>] Array of all available operations
    def to_llm_tools = self.class.operations.keys.map { |k| self[k] }

    private

    attr_reader :_http, :_headers

    # Wraps an Operation to make it executable with HTTP capabilities
    #
    # This class provides two methods to execute operations:
    # - {#run} for general use, returns the full HTTP response
    # - {#call} for RubyLLM Tool compatibility, returns only the response body
    #
    # @example Running an operation
    #   operation = client[:list_pets]
    #   response = operation.run(limit: 10)
    #   puts response.body
    #
    class RunnableOperation < SimpleDelegator
      # Initialize a runnable operation
      #
      # @param op [Smidge::Operation] The operation to wrap
      # @param base_url [URI] The base URL for API requests
      # @param http [HTTPAdapter] HTTP adapter for making requests
      # @param headers [Hash] Custom headers to include in requests
      def initialize(op, base_url, http, headers = {})
        super op
        @base_url = base_url
        @http = http
        @headers = headers
      end

      attr_reader :base_url

      # Execute the operation with the given arguments
      #
      # @param kargs [Hash] Arguments for the operation (path params, query params, body)
      # @return [HTTP::Response] The HTTP response object
      # @example
      #   operation.run(pet_id: 123, limit: 10)
      def run(kargs = {})
        kargs = kargs.dup
        kargs = Plumb::Types::SymbolizedHash.parse(kargs)
        path = path_for(kargs)
        query = query_for(kargs)
        payload = payload_for(kargs)
        uri = URI.join(@base_url, path)
        uri.query = URI.encode_www_form(query) if query.any?
        @http.public_send(verb, uri.to_s, body: payload, headers: REQUEST_HEADERS.merge(@headers))
      end

      # Execute the operation and return only the response body
      #
      # This method is compatible with the RubyLLM Tool interface, making it easy
      # to use Smidge operations as LLM function calling tools.
      #
      # @param args [Hash] Arguments for the operation (path params, query params, body)
      # @return [String, Hash] The response body
      # @example
      #   operation.call(pet_id: 123)
      def call(args = {})
        run(args).body
      end
    end
  end
end
