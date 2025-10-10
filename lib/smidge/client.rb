# frozen_string_literal: true

require 'uri'
require "json"
require "stringio"
require 'smidge/inproc_adapter'
require 'smidge/http_adapter'

module Smidge
  class Client
    REQUEST_HEADERS = { 
      'Content-Type' => 'application/json', 
      'Accept' => 'application/json',
      'User-Agent' => "Smidge::Client/#{Smidge::VERSION} (Ruby/#{RUBY_VERSION})"
    }.freeze

    attr_reader :base_url, :_operations, :_info

    def initialize(operations, base_url:, info: {}, http: HTTPAdapter.new)
      @base_url = Plumb::Types::Forms::URI::HTTP.parse(base_url)

      @_http = http
      @_operations = __build_op_lookup(operations)
      @_info = info
      define_methods!
    end

    def [](name) = _operations[name.to_sym]

    def inspect = %(<#{self.class}:#{object_id} #{base_url} "#{_info['title']}"/#{_info['version']} [#{_operations.size} operations]>)

    def to_llm_tools = _operations.values

    private

    def define_methods!
      _operations.keys.each do |name|
        define_singleton_method(name) do |**kargs|
          _operations[name]
        end
      end
    end

    # Wrap an operation and provide #run(args)
    # to issue requests
    # and #call(args) for RubyLLM Tool compatibility
    class RunnableOperation < SimpleDelegator
      def initialize(op, base_url, http)
        super op
        @base_url = base_url
        @http = http
      end

      def run(kargs = {})
        kargs = kargs.dup
        kargs = Plumb::Types::SymbolizedHash.parse(kargs)
        path = path_for(kargs)
        query = query_for(kargs)
        payload = payload_for(kargs)
        uri = URI.join(@base_url, path)
        uri.query = URI.encode_www_form(query) if query.any?
        @http.public_send(verb, uri.to_s, body: payload, headers: REQUEST_HEADERS)
      end

      # RubyLLM Tool compatible
      def call(args = {})
        run(args).body
      end
    end

    def __build_op_lookup(operations)
      operations.each.with_object({}) do |op, memo|
        memo[op.name] = RunnableOperation.new(op, base_url, @_http)
      end
    end
  end
end
