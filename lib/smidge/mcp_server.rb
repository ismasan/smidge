# frozen_string_literal: true

require 'json'
require 'securerandom'

module Smidge
  # MCP (Model Context Protocol) server that exposes a Smidge::Client as LLM-callable tools
  #
  # This is a Rack-compatible application that implements the MCP Streamable HTTP transport,
  # allowing any OpenAPI-based client to serve its operations as MCP tools.
  #
  # @example Basic usage with config.ru
  #   require 'smidge/mcp_server'
  #
  #   client = Smidge.from_openapi('https://api.example.com/openapi.json')
  #     .with_headers('Authorization' => "Bearer #{ENV['API_KEY']}")
  #
  #   mcp = Smidge::MCPServer.new(client, name: 'My API', version: '1.0')
  #   run mcp
  #
  # @example Mounting alongside other apps
  #   map '/mcp' do
  #     run Smidge::MCPServer.new(client)
  #   end
  #
  class MCPServer
    PROTOCOL_VERSION = '2025-03-26'
    SUPPORTED_VERSIONS = ['2025-03-26', '2024-11-05'].freeze
    JSON_RPC_VERSION = '2.0'
    CONTENT_TYPE_JSON = 'application/json'

    # JSON-RPC error codes
    PARSE_ERROR = -32700
    INVALID_REQUEST = -32600
    METHOD_NOT_FOUND = -32601
    INVALID_PARAMS = -32602
    INTERNAL_ERROR = -32603

    # Headers that are forwarded from MCP requests to the underlying API by default
    DEFAULT_FORWARD_HEADERS = ['Authorization'].freeze

    # Initialize a new MCP server
    #
    # @param client [Smidge::Client] The Smidge client to expose as MCP tools
    # @param name [String, nil] Server name (defaults to client info title)
    # @param version [String] Server version
    # @param instructions [String, nil] Optional instructions for LLM clients
    # @param forward_headers [Array<String>] HTTP headers to forward from MCP requests to the API client
    def initialize(client, name: nil, version: '1.0', instructions: nil, forward_headers: DEFAULT_FORWARD_HEADERS)
      @client = client
      @name = name || client.class.info&.dig('title') || 'Smidge MCP Server'
      @version = version
      @instructions = instructions
      @forward_headers = forward_headers.map(&:downcase)
      @sessions = {} # session_id => { initialized: bool, protocol_version: str }
    end

    attr_reader :client, :name, :version, :instructions

    # Rack interface
    #
    # @param env [Hash] Rack environment
    # @return [Array] Rack response tuple [status, headers, body]
    def call(env)
      request = Rack::Request.new(env)

      case request.request_method
      when 'POST'
        handle_post(request)
      when 'DELETE'
        handle_delete(request)
      when 'OPTIONS'
        handle_options(request)
      else
        method_not_allowed
      end
    rescue JSON::ParserError
      json_rpc_error_response(nil, PARSE_ERROR, 'Parse error')
    rescue => e
      json_rpc_error_response(nil, INTERNAL_ERROR, e.message)
    end

    private

    def handle_post(request)
      # Validate Accept header
      accept = request.get_header('HTTP_ACCEPT') || ''
      unless accept.include?(CONTENT_TYPE_JSON) || accept.include?('*/*') || accept.empty?
        return [406, { 'Content-Type' => CONTENT_TYPE_JSON }, [JSON.dump({ error: 'Not Acceptable' })]]
      end

      body = request.body.read
      return json_rpc_error_response(nil, PARSE_ERROR, 'Empty request body') if body.nil? || body.empty?

      message = JSON.parse(body)
      session_id = request.get_header('HTTP_MCP_SESSION_ID')
      forwarded_headers = extract_forward_headers(request)

      route_message(message, session_id, forwarded_headers)
    end

    def handle_delete(request)
      session_id = request.get_header('HTTP_MCP_SESSION_ID')
      return [400, {}, []] unless session_id

      if @sessions.delete(session_id)
        [204, {}, []]
      else
        [404, {}, []]
      end
    end

    def handle_options(request)
      [204, {
        'Allow' => 'POST, DELETE, OPTIONS',
        'Access-Control-Allow-Methods' => 'POST, DELETE, OPTIONS',
        'Access-Control-Allow-Headers' => 'Content-Type, MCP-Session-Id, Accept'
      }, []]
    end

    def method_not_allowed
      [405, { 'Allow' => 'POST, DELETE, OPTIONS' }, []]
    end

    def route_message(message, session_id, forwarded_headers = {})
      # Handle batch requests
      if message.is_a?(Array)
        results = message.map { |msg| process_single_message(msg, session_id, forwarded_headers) }
        # Filter out nil results (from notifications)
        json_responses = results.filter_map { |r| r[:json_response] }
        return [200, response_headers(session_id), [JSON.dump(json_responses)]] if json_responses.any?
        return [204, {}, []]
      end

      result = process_single_message(message, session_id, forwarded_headers)
      result[:rack_response] || [200, response_headers(session_id), [JSON.dump(result[:json_response])]]
    end

    def process_single_message(message, session_id, forwarded_headers = {})
      unless message.is_a?(Hash)
        return { json_response: json_rpc_error(nil, INVALID_REQUEST, 'Invalid request') }
      end

      jsonrpc = message['jsonrpc']
      unless jsonrpc == JSON_RPC_VERSION
        return { json_response: json_rpc_error(nil, INVALID_REQUEST, 'Invalid JSON-RPC version') }
      end

      method_name = message['method']
      id = message['id']
      params = message['params'] || {}

      # Notifications have no id
      is_notification = id.nil?

      case method_name
      when 'initialize'
        handle_initialize(id, params)
      when 'notifications/initialized'
        handle_initialized(session_id)
      when 'tools/list'
        handle_tools_list(id, params, session_id)
      when 'tools/call'
        handle_tools_call(id, params, session_id, forwarded_headers)
      when 'ping'
        handle_ping(id)
      else
        if is_notification
          # Unknown notifications are ignored per spec
          { rack_response: [204, {}, []] }
        else
          { json_response: json_rpc_error(id, METHOD_NOT_FOUND, "Method not found: #{method_name}") }
        end
      end
    end

    def handle_initialize(id, params)
      client_protocol_version = params['protocolVersion']

      # Negotiate protocol version
      negotiated_version = if SUPPORTED_VERSIONS.include?(client_protocol_version)
        client_protocol_version
      else
        PROTOCOL_VERSION
      end

      session_id = SecureRandom.uuid
      @sessions[session_id] = { initialized: false, protocol_version: negotiated_version }

      result = {
        'protocolVersion' => negotiated_version,
        'capabilities' => { 'tools' => {} },
        'serverInfo' => {
          'name' => @name,
          'version' => @version
        }
      }
      result['instructions'] = @instructions if @instructions

      # Initialize is special: it needs to set the session header
      { rack_response: [200, response_headers(session_id), [JSON.dump(json_rpc_result(id, result))]] }
    end

    def handle_initialized(session_id)
      if session_id && @sessions[session_id]
        @sessions[session_id][:initialized] = true
      end
      # Return 202 Accepted for notifications
      { rack_response: [202, {}, []] }
    end

    def handle_tools_list(id, params, session_id)
      tools = @client.class.operations.values.map { |op| operation_to_tool(op) }
      result = { 'tools' => tools }
      { json_response: json_rpc_result(id, result) }
    end

    def handle_tools_call(id, params, session_id, forwarded_headers = {})
      tool_name = params['name']
      arguments = params['arguments'] || {}

      begin
        op_name = tool_name.to_sym
        unless @client.class.operations.key?(op_name)
          return { json_response: json_rpc_error(id, INVALID_PARAMS, "Unknown tool: #{tool_name}") }
        end

        # Use client with forwarded headers if any are present
        client = forwarded_headers.empty? ? @client : @client.with_headers(forwarded_headers)

        # Symbolize argument keys
        symbolized_args = arguments.transform_keys(&:to_sym)
        result = client[op_name].call(symbolized_args)

        content = if result.is_a?(String)
          result
        else
          JSON.dump(result)
        end

        { json_response: json_rpc_result(id, {
          'content' => [{ 'type' => 'text', 'text' => content }],
          'isError' => false
        }) }
      rescue => e
        { json_response: json_rpc_result(id, {
          'content' => [{ 'type' => 'text', 'text' => e.message }],
          'isError' => true
        }) }
      end
    end

    def handle_ping(id)
      { json_response: json_rpc_result(id, {}) }
    end

    def operation_to_tool(op)
      properties = {}
      required = []

      op.parameters.each do |name, param|
        properties[name.to_s] = {
          'type' => param_type_to_json_schema(param.type)
        }.tap do |prop|
          prop['description'] = param.description unless param.description.to_s.empty?
        end
        required << name.to_s if param.required
      end

      tool = {
        'name' => op.name.to_s,
        'inputSchema' => {
          'type' => 'object',
          'properties' => properties
        }
      }
      tool['description'] = op.description if op.description && !op.description.empty?
      tool['inputSchema']['required'] = required unless required.empty?
      tool
    end

    def param_type_to_json_schema(type)
      case type.to_s
      when 'string' then 'string'
      when 'integer', 'int' then 'integer'
      when 'number', 'float', 'double' then 'number'
      when 'boolean', 'bool' then 'boolean'
      when 'array' then 'array'
      when 'object' then 'object'
      else 'string'
      end
    end

    def json_rpc_result(id, result)
      {
        'jsonrpc' => JSON_RPC_VERSION,
        'id' => id,
        'result' => result
      }
    end

    def json_rpc_error(id, code, message, data = nil)
      error = {
        'code' => code,
        'message' => message
      }
      error['data'] = data if data

      {
        'jsonrpc' => JSON_RPC_VERSION,
        'id' => id,
        'error' => error
      }
    end

    def json_rpc_error_response(id, code, message, data = nil)
      [200, response_headers, [JSON.dump(json_rpc_error(id, code, message, data))]]
    end

    def response_headers(session_id = nil)
      headers = { 'Content-Type' => CONTENT_TYPE_JSON }
      headers['MCP-Session-Id'] = session_id if session_id
      headers
    end

    # Extract headers to forward from the Rack request
    #
    # @param request [Rack::Request] The incoming request
    # @return [Hash] Headers to forward to the API client
    def extract_forward_headers(request)
      @forward_headers.each_with_object({}) do |header_name, result|
        # Rack converts headers to HTTP_* format (e.g., Authorization -> HTTP_AUTHORIZATION)
        rack_key = "HTTP_#{header_name.upcase.tr('-', '_')}"
        value = request.get_header(rack_key)
        result[header_name.split('-').map(&:capitalize).join('-')] = value if value
      end
    end
  end
end
