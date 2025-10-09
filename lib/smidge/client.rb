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

    class Param
      attr_reader :name, :type, :description, :example, :required

      def initialize(attrs)
        @name = attrs.fetch(:name).to_sym
        @type = attrs.fetch(:type, :string).to_sym
        @description = attrs[:description].to_s
        @example = attrs[:example].to_s
        @description = [@description, "(eg #{@example})"].join(' ') unless @example.empty?
        @required = attrs.fetch(:required, false)
        freeze
      end
    end

    class Op < Data.define(:rel_name, :verb, :path, :description, :path_params, :query_params, :body_params)
      def self.build(verb, path, details)
        rel_name = details['operationId'].to_s.strip
        description = details['description'] || details['summary'] || ''
        parameters = (details['parameters'] || [])
        path_params = build_params(parameters.select { |p| p['in'] == 'path' })
        query_params = build_params(parameters.select { |p| p['in'] == 'query' })
        bschema = details.dig('requestBody', 'content', 'application/json', 'schema') || {}
        required = (bschema['required'] || [])
        body_params = (bschema['properties'] || {}).map do |name, prop|
          attrs = {name:, required: required.include?(name)}.merge(Plumb::Types::SymbolizedHash.parse(prop))
          Param.new(attrs)
        end

        rel_name = "#{verb}_#{path}" if rel_name.empty?
        raise InvalidSpecError, "Operation missing HTTP verb" if verb.to_s.empty?
        raise InvalidSpecError, "Operation missing HTTP path" if path.to_s.empty?

        new(
          rel_name: Smidge.to_method_name(rel_name).to_sym, 
          verb: verb.to_sym, 
          path:, 
          description:, 
          path_params:, 
          query_params:, 
          body_params:
        )
      end

      def self.build_params(list)
        list.map do |param|
          Param.new(Plumb::Types::SymbolizedHash.parse(param))
        end
      end

      def params
        path_params + query_params + body_params
      end

      # A tool class compatible with RubyLLM::Tool
      class Tool
        attr_reader :parameters

        def initialize(op, client)
          @op = op
          @client = client
          @parameters = op.params.each_with_object({}) do |p, memo|
            memo[p.name] = p
          end
        end

        def inspect = %(<#{self.class}:#{object_id} [#{name}] #{parameters.values.map(&:name).join(', ')}>)
        def name = @op.rel_name.to_s
        def description = @op.description.to_s
        def call(args)
          args = Plumb::Types::SymbolizedHash.parse(args)
          @client.send(@op.rel_name, **args).body
        end
      end

      def to_tool(client)
        Tool.new(self, client)
      end

      def path_for(kargs)
        path_params.reduce(path) do |tpath, param|
          if kargs.key?(param.name)
            tpath.gsub("{#{param.name}}", kargs.delete(param.name).to_s)
          else
            tpath
          end
        end
      end

      def query_for(kargs)
        query_params.each_with_object({}) do |param, memo|
          memo[param.name] = kargs.delete(param.name) if kargs.key?(param.name)
        end
      end

      def payload_for(kargs)
        body_params.each_with_object({}) do |param, memo|
          memo[param.name] = kargs.delete(param.name) if kargs.key?(param.name)
        end
      end
    end

    attr_reader :base_url, :_operations, :_info

    def initialize(spec, http: HTTPAdapter.new, base_url: nil)
      @base_url = base_url ? URI(base_url) : __find_base_url(spec)
      raise ArgumentError, "Base URL is required" unless @base_url

      @_http = http
      @_operations = __build_op_lookup(spec)
      @_info = spec['info'] || {}
      define_methods!
    end

    def [](rel_name) = _operations[rel_name.to_sym]

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

    def __find_base_url(spec)
      srv = spec['servers']&.first
      srv ? URI(srv['url']) : nil
    end

    def __build_op_lookup(spec)
      raise InvalidSpecError, "Spec missing 'paths'" unless spec['paths'].is_a?(Hash)

      opts = {}
      spec['paths'].each do |path, verbs|
        verbs.each do |verb, details|
          op = Op.build(verb, path, details)
          opts[op.rel_name] = op
        end
      end

      opts
    end
  end
end
