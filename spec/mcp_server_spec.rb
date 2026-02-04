# frozen_string_literal: true

require 'spec_helper'
require 'smidge/mcp_server'
require 'rack'

RSpec.describe Smidge::MCPServer do
  let(:client_class) do
    Class.new(Smidge::Client) do
      info 'title' => 'Test API', 'version' => '1.0.0'

      operation name: :list_users, verb: :get, path: '/users', description: 'List all users' do |op|
        op.param name: 'q', type: 'string', description: 'Search query'
        op.param name: 'limit', type: 'integer', description: 'Max results'
      end

      operation name: :get_user, verb: :get, path: '/users/{id}', description: 'Get a user by ID' do |op|
        op.param name: 'id', in: 'path', type: 'integer', required: true, description: 'User ID'
      end

      operation name: :create_user, verb: :post, path: '/users', description: 'Create a new user' do |op|
        op.param name: 'name', in: 'body', type: 'string', required: true, description: 'User name'
        op.param name: 'email', in: 'body', type: 'string', required: true, description: 'User email'
      end
    end
  end

  let(:http_adapter) { double('http') }
  let(:client) { client_class.new(base_url: 'http://api.test', http: http_adapter) }
  subject(:mcp) { described_class.new(client, name: 'Test MCP Server', version: '2.0') }

  def post_json(body, headers = {})
    env = Rack::MockRequest.env_for(
      '/',
      method: 'POST',
      input: JSON.dump(body),
      'CONTENT_TYPE' => 'application/json',
      'HTTP_ACCEPT' => 'application/json'
    )
    headers.each { |k, v| env["HTTP_#{k.upcase.tr('-', '_')}"] = v }
    mcp.call(env)
  end

  def delete_request(session_id)
    env = Rack::MockRequest.env_for('/', method: 'DELETE')
    env['HTTP_MCP_SESSION_ID'] = session_id
    mcp.call(env)
  end

  def parse_response(response)
    status, headers, body = response
    body_str = body.map(&:to_s).join
    [status, headers, body_str.empty? ? nil : JSON.parse(body_str)]
  end

  describe 'HTTP methods' do
    it 'returns 405 for unsupported methods' do
      env = Rack::MockRequest.env_for('/', method: 'GET')
      status, headers, _body = mcp.call(env)

      expect(status).to eq(405)
      expect(headers['Allow']).to eq('POST, DELETE, OPTIONS')
    end

    it 'handles OPTIONS requests for CORS' do
      env = Rack::MockRequest.env_for('/', method: 'OPTIONS')
      status, headers, _body = mcp.call(env)

      expect(status).to eq(204)
      expect(headers['Allow']).to eq('POST, DELETE, OPTIONS')
      expect(headers['Access-Control-Allow-Methods']).to eq('POST, DELETE, OPTIONS')
    end
  end

  describe 'JSON-RPC error handling' do
    it 'returns parse error for invalid JSON' do
      env = Rack::MockRequest.env_for(
        '/',
        method: 'POST',
        input: 'invalid json{',
        'CONTENT_TYPE' => 'application/json',
        'HTTP_ACCEPT' => 'application/json'
      )
      status, _headers, body = parse_response(mcp.call(env))

      expect(status).to eq(200)
      expect(body['error']['code']).to eq(-32700)
      expect(body['error']['message']).to eq('Parse error')
    end

    it 'returns parse error for empty body' do
      env = Rack::MockRequest.env_for(
        '/',
        method: 'POST',
        input: '',
        'CONTENT_TYPE' => 'application/json',
        'HTTP_ACCEPT' => 'application/json'
      )
      status, _headers, body = parse_response(mcp.call(env))

      expect(status).to eq(200)
      expect(body['error']['code']).to eq(-32700)
    end

    it 'returns invalid request for non-object messages' do
      status, _headers, body = parse_response(post_json('string'))

      expect(status).to eq(200)
      expect(body['error']['code']).to eq(-32600)
    end

    it 'returns invalid request for wrong JSON-RPC version' do
      status, _headers, body = parse_response(post_json({
        'jsonrpc' => '1.0',
        'id' => 1,
        'method' => 'ping'
      }))

      expect(status).to eq(200)
      expect(body['error']['code']).to eq(-32600)
      expect(body['error']['message']).to eq('Invalid JSON-RPC version')
    end

    it 'returns method not found for unknown methods' do
      status, _headers, body = parse_response(post_json({
        'jsonrpc' => '2.0',
        'id' => 1,
        'method' => 'unknown/method'
      }))

      expect(status).to eq(200)
      expect(body['error']['code']).to eq(-32601)
      expect(body['error']['message']).to include('unknown/method')
    end
  end

  describe 'initialize method' do
    it 'returns server capabilities and info' do
      status, headers, body = parse_response(post_json({
        'jsonrpc' => '2.0',
        'id' => 1,
        'method' => 'initialize',
        'params' => {
          'protocolVersion' => '2025-03-26',
          'capabilities' => {},
          'clientInfo' => { 'name' => 'test-client', 'version' => '1.0' }
        }
      }))

      expect(status).to eq(200)
      expect(body['jsonrpc']).to eq('2.0')
      expect(body['id']).to eq(1)
      expect(body['result']['protocolVersion']).to eq('2025-03-26')
      expect(body['result']['capabilities']).to eq({ 'tools' => {} })
      expect(body['result']['serverInfo']['name']).to eq('Test MCP Server')
      expect(body['result']['serverInfo']['version']).to eq('2.0')
      expect(headers['MCP-Session-Id']).to be_a(String)
    end

    it 'negotiates protocol version' do
      status, _headers, body = parse_response(post_json({
        'jsonrpc' => '2.0',
        'id' => 1,
        'method' => 'initialize',
        'params' => {
          'protocolVersion' => '2024-11-05',
          'capabilities' => {},
          'clientInfo' => { 'name' => 'test' }
        }
      }))

      expect(status).to eq(200)
      expect(body['result']['protocolVersion']).to eq('2024-11-05')
    end

    it 'falls back to default version for unsupported client versions' do
      status, _headers, body = parse_response(post_json({
        'jsonrpc' => '2.0',
        'id' => 1,
        'method' => 'initialize',
        'params' => {
          'protocolVersion' => '2020-01-01',
          'capabilities' => {},
          'clientInfo' => { 'name' => 'test' }
        }
      }))

      expect(status).to eq(200)
      expect(body['result']['protocolVersion']).to eq('2025-03-26')
    end

    context 'with instructions' do
      subject(:mcp) { described_class.new(client, instructions: 'Use this API for user management') }

      it 'includes instructions in response' do
        status, _headers, body = parse_response(post_json({
          'jsonrpc' => '2.0',
          'id' => 1,
          'method' => 'initialize',
          'params' => { 'protocolVersion' => '2025-03-26', 'capabilities' => {}, 'clientInfo' => { 'name' => 'test' } }
        }))

        expect(status).to eq(200)
        expect(body['result']['instructions']).to eq('Use this API for user management')
      end
    end

    context 'with default name from client' do
      subject(:mcp) { described_class.new(client) }

      it 'uses client info title as server name' do
        status, _headers, body = parse_response(post_json({
          'jsonrpc' => '2.0',
          'id' => 1,
          'method' => 'initialize',
          'params' => { 'protocolVersion' => '2025-03-26', 'capabilities' => {}, 'clientInfo' => { 'name' => 'test' } }
        }))

        expect(body['result']['serverInfo']['name']).to eq('Test API')
      end
    end
  end

  describe 'notifications/initialized' do
    it 'returns 202 Accepted' do
      # First initialize to get a session
      _status, headers, _body = parse_response(post_json({
        'jsonrpc' => '2.0',
        'id' => 1,
        'method' => 'initialize',
        'params' => { 'protocolVersion' => '2025-03-26', 'capabilities' => {}, 'clientInfo' => { 'name' => 'test' } }
      }))

      session_id = headers['MCP-Session-Id']

      status, _headers, body = post_json({
        'jsonrpc' => '2.0',
        'method' => 'notifications/initialized'
      }, { 'MCP-Session-Id' => session_id })

      expect(status).to eq(202)
      expect(body.join).to be_empty
    end
  end

  describe 'ping method' do
    it 'returns empty result' do
      status, _headers, body = parse_response(post_json({
        'jsonrpc' => '2.0',
        'id' => 42,
        'method' => 'ping'
      }))

      expect(status).to eq(200)
      expect(body['id']).to eq(42)
      expect(body['result']).to eq({})
    end
  end

  describe 'tools/list method' do
    it 'returns all operations as tools' do
      status, _headers, body = parse_response(post_json({
        'jsonrpc' => '2.0',
        'id' => 1,
        'method' => 'tools/list'
      }))

      expect(status).to eq(200)
      expect(body['result']['tools']).to be_an(Array)
      expect(body['result']['tools'].length).to eq(3)

      tool_names = body['result']['tools'].map { |t| t['name'] }
      expect(tool_names).to contain_exactly('list_users', 'get_user', 'create_user')
    end

    it 'includes tool descriptions' do
      status, _headers, body = parse_response(post_json({
        'jsonrpc' => '2.0',
        'id' => 1,
        'method' => 'tools/list'
      }))

      list_users_tool = body['result']['tools'].find { |t| t['name'] == 'list_users' }
      expect(list_users_tool['description']).to eq('List all users')
    end

    it 'includes JSON Schema for parameters' do
      status, _headers, body = parse_response(post_json({
        'jsonrpc' => '2.0',
        'id' => 1,
        'method' => 'tools/list'
      }))

      list_users_tool = body['result']['tools'].find { |t| t['name'] == 'list_users' }
      schema = list_users_tool['inputSchema']

      expect(schema['type']).to eq('object')
      expect(schema['properties']['q']['type']).to eq('string')
      expect(schema['properties']['q']['description']).to eq('Search query')
      expect(schema['properties']['limit']['type']).to eq('integer')
      expect(schema['properties']['limit']['description']).to eq('Max results')
    end

    it 'includes required parameters' do
      status, _headers, body = parse_response(post_json({
        'jsonrpc' => '2.0',
        'id' => 1,
        'method' => 'tools/list'
      }))

      create_user_tool = body['result']['tools'].find { |t| t['name'] == 'create_user' }
      expect(create_user_tool['inputSchema']['required']).to contain_exactly('name', 'email')
    end

    it 'omits required key when no parameters are required' do
      status, _headers, body = parse_response(post_json({
        'jsonrpc' => '2.0',
        'id' => 1,
        'method' => 'tools/list'
      }))

      list_users_tool = body['result']['tools'].find { |t| t['name'] == 'list_users' }
      expect(list_users_tool['inputSchema']).not_to have_key('required')
    end
  end

  describe 'tools/call method' do
    it 'executes the tool and returns result' do
      response = double('response', body: [{ id: 1, name: 'Alice' }])
      expect(http_adapter).to receive(:get).and_return(response)

      status, _headers, body = parse_response(post_json({
        'jsonrpc' => '2.0',
        'id' => 1,
        'method' => 'tools/call',
        'params' => {
          'name' => 'list_users',
          'arguments' => { 'q' => 'alice' }
        }
      }))

      expect(status).to eq(200)
      expect(body['result']['isError']).to eq(false)
      expect(body['result']['content']).to be_an(Array)
      expect(body['result']['content'].first['type']).to eq('text')

      result_data = JSON.parse(body['result']['content'].first['text'])
      expect(result_data).to eq([{ 'id' => 1, 'name' => 'Alice' }])
    end

    it 'handles string responses' do
      response = double('response', body: 'plain text response')
      expect(http_adapter).to receive(:get).and_return(response)

      status, _headers, body = parse_response(post_json({
        'jsonrpc' => '2.0',
        'id' => 1,
        'method' => 'tools/call',
        'params' => {
          'name' => 'list_users',
          'arguments' => {}
        }
      }))

      expect(status).to eq(200)
      expect(body['result']['content'].first['text']).to eq('plain text response')
    end

    it 'returns error for unknown tool' do
      status, _headers, body = parse_response(post_json({
        'jsonrpc' => '2.0',
        'id' => 1,
        'method' => 'tools/call',
        'params' => {
          'name' => 'unknown_tool',
          'arguments' => {}
        }
      }))

      expect(status).to eq(200)
      expect(body['error']['code']).to eq(-32602)
      expect(body['error']['message']).to include('Unknown tool')
    end

    it 'returns tool error in result when execution fails' do
      expect(http_adapter).to receive(:get).and_raise(StandardError.new('Connection failed'))

      status, _headers, body = parse_response(post_json({
        'jsonrpc' => '2.0',
        'id' => 1,
        'method' => 'tools/call',
        'params' => {
          'name' => 'list_users',
          'arguments' => {}
        }
      }))

      expect(status).to eq(200)
      expect(body['result']['isError']).to eq(true)
      expect(body['result']['content'].first['text']).to eq('Connection failed')
    end

    it 'handles arguments with path parameters' do
      response = double('response', body: { id: 1, name: 'Alice' })
      expect(http_adapter).to receive(:get)
        .with('http://api.test/users/42', anything)
        .and_return(response)

      status, _headers, body = parse_response(post_json({
        'jsonrpc' => '2.0',
        'id' => 1,
        'method' => 'tools/call',
        'params' => {
          'name' => 'get_user',
          'arguments' => { 'id' => 42 }
        }
      }))

      expect(status).to eq(200)
      expect(body['result']['isError']).to eq(false)
    end
  end

  describe 'session management' do
    it 'can delete a session' do
      # Initialize to create a session
      _status, headers, _body = parse_response(post_json({
        'jsonrpc' => '2.0',
        'id' => 1,
        'method' => 'initialize',
        'params' => { 'protocolVersion' => '2025-03-26', 'capabilities' => {}, 'clientInfo' => { 'name' => 'test' } }
      }))

      session_id = headers['MCP-Session-Id']

      # Delete the session
      status, _headers, _body = delete_request(session_id)
      expect(status).to eq(204)

      # Deleting again should return 404
      status, _headers, _body = delete_request(session_id)
      expect(status).to eq(404)
    end

    it 'returns 400 for DELETE without session ID' do
      env = Rack::MockRequest.env_for('/', method: 'DELETE')
      status, _headers, _body = mcp.call(env)

      expect(status).to eq(400)
    end
  end

  describe 'batch requests' do
    it 'handles multiple requests in a batch' do
      status, _headers, body = parse_response(post_json([
        { 'jsonrpc' => '2.0', 'id' => 1, 'method' => 'ping' },
        { 'jsonrpc' => '2.0', 'id' => 2, 'method' => 'tools/list' }
      ]))

      expect(status).to eq(200)
      expect(body).to be_an(Array)
      expect(body.length).to eq(2)

      ping_response = body.find { |r| r['id'] == 1 }
      expect(ping_response['result']).to eq({})

      tools_response = body.find { |r| r['id'] == 2 }
      expect(tools_response['result']['tools']).to be_an(Array)
    end
  end

  describe 'type mapping' do
    let(:client_class) do
      Class.new(Smidge::Client) do
        info 'title' => 'Type Test API'

        operation name: :test_types, verb: :get, path: '/test' do |op|
          op.param name: 'str', type: 'string'
          op.param name: 'int', type: 'integer'
          op.param name: 'num', type: 'number'
          op.param name: 'bool', type: 'boolean'
          op.param name: 'arr', type: 'array'
          op.param name: 'obj', type: 'object'
          op.param name: 'unknown', type: 'custom'
        end
      end
    end

    it 'maps Smidge types to JSON Schema types' do
      status, _headers, body = parse_response(post_json({
        'jsonrpc' => '2.0',
        'id' => 1,
        'method' => 'tools/list'
      }))

      tool = body['result']['tools'].first
      props = tool['inputSchema']['properties']

      expect(props['str']['type']).to eq('string')
      expect(props['int']['type']).to eq('integer')
      expect(props['num']['type']).to eq('number')
      expect(props['bool']['type']).to eq('boolean')
      expect(props['arr']['type']).to eq('array')
      expect(props['obj']['type']).to eq('object')
      expect(props['unknown']['type']).to eq('string') # fallback
    end
  end

  describe 'unknown notifications' do
    it 'ignores unknown notifications (no id)' do
      status, _headers, body = post_json({
        'jsonrpc' => '2.0',
        'method' => 'unknown/notification'
      })

      expect(status).to eq(204)
      expect(body.join).to be_empty
    end
  end
end
