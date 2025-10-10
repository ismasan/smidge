# frozen_string_literal: true

module Smidge
  class Operation
    attr_reader :name, :verb, :path, :description, :parameters

    def initialize(name:, verb:, path:, description:, parameters: {})
      @name = name
      @verb = verb
      @path = path
      @description = description
      @params_in = { 'query' => [], 'path' => [], 'body' => [] }
      @parameters = parameters.each.with_object({}) do |param, memo|
        @params_in[param.in] << param
        memo[param.name.to_sym] = param
      end.freeze

      @params_in.freeze
      freeze
    end

    class Param
      attr_reader :in, :name, :type, :description, :example, :required

      def initialize(attrs)
        @in = attrs.fetch(:in)
        @name = attrs.fetch(:name).to_sym
        @type = attrs.fetch(:type, :string).to_sym
        @description = attrs[:description].to_s
        @example = attrs[:example].to_s
        @description = [@description, "(eg #{@example})"].join(' ') unless @example.empty?
        @required = attrs.fetch(:required, false)
        freeze
      end
    end

    # A tool class compatible with RubyLLM::Tool
    class Tool
      attr_reader :parameters

      def initialize(op, client)
        @op = op
        @client = client
        @parameters = op.parameters.values.each_with_object({}) do |p, memo|
          memo[p.name] = p
        end
      end

      def inspect = %(<#{self.class}:#{object_id} [#{name}] #{parameters.values.map(&:name).join(', ')}>)
      def name = @op.name.to_s
      def description = @op.description.to_s
      def call(args)
        args = Plumb::Types::SymbolizedHash.parse(args)
        @client.send(@op.name, **args).body
      end
    end

    def to_tool(client)
      Tool.new(self, client)
    end

    def path_for(kargs)
      @params_in['path'].reduce(path) do |tpath, param|
        if kargs.key?(param.name)
          tpath.gsub("{#{param.name}}", kargs.delete(param.name).to_s)
        else
          tpath
        end
      end
    end

    def query_for(kargs)
      @params_in['query'].each_with_object({}) do |param, memo|
        memo[param.name] = kargs.delete(param.name) if kargs.key?(param.name)
      end
    end

    def payload_for(kargs)
      @params_in['body'].each_with_object({}) do |param, memo|
        memo[param.name] = kargs.delete(param.name) if kargs.key?(param.name)
      end
    end
  end
end
