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

    def to_llm_tools = _operations.values.map { |op| op.to_tool(self) }

    private

    def define_methods!
      _operations.each do |name, op|
        define_singleton_method(name) do |**kargs|
          _run_op(op, **kargs)
        end
      end
    end

    def _run_op(op, **kargs)
      kargs = kargs.dup
      path = op.path_for(kargs)
      query = op.query_for(kargs)
      payload = op.payload_for(kargs)
      uri = URI.join(base_url, path)
      uri.query = URI.encode_www_form(query) if query.any?
      @_http.public_send(op.verb, uri.to_s, body: payload, headers: REQUEST_HEADERS)
    end

    def __build_op_lookup(operations)
      operations.each.with_object({}) do |op, memo|
        memo[op.name] = op
      end
    end
  end
end
