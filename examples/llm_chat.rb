# frozen_string_literal: true

require 'bundler'
Bundler.setup(:llms)

require 'smidge'
require 'ruby_llm'
require 'debug'

# Point it to an OpenAPI spec
# Run with
#   OPENAI_API_KEY=xxx OPEN_API=<URL> bundle exec exec ruby examples/llm_chat.rb
#
RubyLLM.configure do |config|
  config.openai_api_key = ENV.fetch('OPENAI_API_KEY')
end

OPEN_API_URL = ENV.fetch('OPEN_API', 'http://localhost:9292')

# Bootstrap Smidle client from OpenAPI spec
CLIENT = Smidge.from_openapi(OPEN_API_URL, base_url: OPEN_API_URL)

# Use the client's OpenAPI spec
# to create RubyLLM-compatible tool classes
# that call the endpoints over HTTP
#
tools = CLIENT.to_llm_tools
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


