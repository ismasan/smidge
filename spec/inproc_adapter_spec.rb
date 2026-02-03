# frozen_string_literal: true

require 'spec_helper'
require 'smidge/inproc_adapter'

RSpec.describe Smidge::InprocAdapter do
  let(:rack_app) do
    lambda do |env|
      request = Rack::Request.new(env)

      case [request.request_method, request.path_info]
      when ['GET', '/users']
        [200, {'Content-Type' => 'application/json'}, [JSON.dump([{id: 1, name: 'Alice'}])]]
      when ['GET', '/users/1']
        [200, {'Content-Type' => 'application/json'}, [JSON.dump({id: 1, name: 'Alice'})]]
      when ['POST', '/users']
        body = JSON.parse(request.body.read, symbolize_names: true)
        [201, {'Content-Type' => 'application/json'}, [JSON.dump({id: 2, name: body[:name]})]]
      when ['PUT', '/users/1']
        body = JSON.parse(request.body.read, symbolize_names: true)
        [200, {'Content-Type' => 'application/json'}, [JSON.dump({id: 1, name: body[:name]})]]
      when ['PATCH', '/users/1']
        body = JSON.parse(request.body.read, symbolize_names: true)
        [200, {'Content-Type' => 'application/json'}, [JSON.dump({id: 1, name: body[:name]})]]
      when ['DELETE', '/users/1']
        [204, {}, []]
      when ['GET', '/text']
        [200, {'Content-Type' => 'text/plain'}, ['Hello, World!']]
      when ['GET', '/echo-headers']
        auth = env['HTTP_AUTHORIZATION']
        [200, {'Content-Type' => 'application/json'}, [JSON.dump({authorization: auth})]]
      else
        [404, {'Content-Type' => 'application/json'}, [JSON.dump({error: 'Not found'})]]
      end
    end
  end

  subject(:adapter) { described_class.new(rack_app) }

  describe '#get' do
    it 'sends GET request and returns parsed JSON response' do
      response = adapter.get('http://test/users')

      expect(response).to be_a(Net::HTTPSuccess)
      expect(response.code).to eq('200')
      expect(response.body).to eq([{id: 1, name: 'Alice'}])
    end

    it 'handles path parameters' do
      response = adapter.get('http://test/users/1')

      expect(response.code).to eq('200')
      expect(response.body).to eq({id: 1, name: 'Alice'})
    end

    it 'returns non-JSON body as string' do
      response = adapter.get('http://test/text')

      expect(response.code).to eq('200')
      expect(response.body).to eq('Hello, World!')
    end

    it 'passes headers to the request' do
      response = adapter.get('http://test/echo-headers', headers: {'Authorization' => 'Bearer token123'})

      expect(response.body[:authorization]).to eq('Bearer token123')
    end

    it 'supports symbolize_names: false' do
      response = adapter.get('http://test/users/1', symbolize_names: false)

      expect(response.body).to eq({'id' => 1, 'name' => 'Alice'})
    end
  end

  describe '#post' do
    it 'sends POST request with JSON body' do
      response = adapter.post('http://test/users', body: {name: 'Bob'})

      expect(response).to be_a(Net::HTTPCreated)
      expect(response.code).to eq('201')
      expect(response.body).to eq({id: 2, name: 'Bob'})
    end
  end

  describe '#put' do
    it 'sends PUT request with JSON body' do
      response = adapter.put('http://test/users/1', body: {name: 'Updated'})

      expect(response.code).to eq('200')
      expect(response.body).to eq({id: 1, name: 'Updated'})
    end
  end

  describe '#patch' do
    it 'sends PATCH request with JSON body' do
      response = adapter.patch('http://test/users/1', body: {name: 'Patched'})

      expect(response.code).to eq('200')
      expect(response.body).to eq({id: 1, name: 'Patched'})
    end
  end

  describe '#delete' do
    it 'sends DELETE request' do
      response = adapter.delete('http://test/users/1')

      expect(response).to be_a(Net::HTTPNoContent)
      expect(response.code).to eq('204')
    end
  end

  describe 'error responses' do
    it 'returns appropriate HTTP response class for 404' do
      response = adapter.get('http://test/not-found')

      expect(response).to be_a(Net::HTTPNotFound)
      expect(response.code).to eq('404')
      expect(response.body).to eq({error: 'Not found'})
    end
  end

  describe 'integration with Smidge::Client' do
    let(:client_class) do
      Class.new(Smidge::Client) do
        info 'title' => 'Test API'

        operation name: :list_users, verb: :get, path: '/users'
        operation name: :get_user, verb: :get, path: '/users/{id}' do |op|
          op.param name: 'id', in: 'path', type: 'integer', required: true
        end
        operation name: :create_user, verb: :post, path: '/users' do |op|
          op.param name: 'name', in: 'body', type: 'string', required: true
        end
        operation name: :update_user, verb: :put, path: '/users/{id}' do |op|
          op.param name: 'id', in: 'path', type: 'integer', required: true
          op.param name: 'name', in: 'body', type: 'string', required: true
        end
        operation name: :delete_user, verb: :delete, path: '/users/{id}' do |op|
          op.param name: 'id', in: 'path', type: 'integer', required: true
        end
      end
    end

    let(:client) { client_class.new(base_url: 'http://test', http: adapter) }

    it 'works with GET requests' do
      response = client.list_users
      expect(response.body).to eq([{id: 1, name: 'Alice'}])
    end

    it 'works with path parameters' do
      response = client.get_user(id: 1)
      expect(response.body).to eq({id: 1, name: 'Alice'})
    end

    it 'works with POST requests' do
      response = client.create_user(name: 'Bob')
      expect(response.body).to eq({id: 2, name: 'Bob'})
    end

    it 'works with PUT requests' do
      response = client.update_user(id: 1, name: 'Updated')
      expect(response.body).to eq({id: 1, name: 'Updated'})
    end

    it 'works with DELETE requests' do
      response = client.delete_user(id: 1)
      expect(response.code).to eq('204')
    end
  end
end
