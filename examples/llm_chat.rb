# frozen_string_literal: true

require 'bundler'
Bundler.setup(:llms)

require 'smidge'
require 'ruby_llm'
require 'debug'

module Smidge
  class LLMTool < RubyLLM::Tool
    def self.from_client(client)
      client._operations.values.map do |op|
        from_op(op).new(client, op)
      end
    end

    def self.from_op(op)
      Class.new(self).tap do |k|
        k.description op.description
        op.params.each do |param|
          k.param param.name, type: param.type, desc: param.description_with_example, required: param.required
        end
      end
    end

    def initialize(client, op)
      @client = client
      @op = op
    end

    def name = @op.rel_name.to_s

    def execute(**kargs)
      @client.send(@op.rel_name, **kargs).body
    end
  end
end

RubyLLM.configure do |config|
  config.openai_api_key = ENV.fetch('OPENAI_API_KEY')
end

CLIENT = Smidge.from_openapi('http://localhost:9292', base_url: 'http://localhost:9292')

# Use the client's OpenAPI spec
# to create RubyLLM tool classes
# that call the endpoints over HTTP
#
tools = Smidge::LLMTool.from_client(CLIENT)
chat = RubyLLM.chat.with_tools(*tools)

while (true) do
  puts 'You:'
  input = $stdin.gets.strip
  if input == 'quit'
    puts "Exiting..."
    break
  elsif !input.empty?
    # Ask a question
    response = chat.ask input

    puts
    puts "AI:"
    # The response is a RubyLLM::Message object
    puts response.content
    puts
  end
end

puts 'bye'


