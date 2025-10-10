# frozen_string_literal: true

module Smidge
  class Operation < ::Data.define(:rel_name, :verb, :path, :description, :path_params, :query_params, :body_params)
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

    def params
      path_params + query_params + body_params
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
end
