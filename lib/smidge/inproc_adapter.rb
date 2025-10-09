# frozen_string_literal: true

module Smidge
  class InprocAdapter
    def initialize(app)
      @app = app
    end

    def get(url, body: nil, headers: nil, symbolize_names: true)
      request(:get, url, body, headers, symbolize_names:)
    end

    def put(url, body: nil, headers: nil)
      request(:put, url, body, headers)
    end

    def post(url, body: nil, headers: nil)
      request(:post, url, body, headers)
    end

    def patch(url, body: nil, headers: nil)
      request(:patch, url, body, headers)
    end

    def delete(url, body: nil, headers: nil)
      request(:delete, url, body, headers)
    end

    JSON_MIME = 'application/json'

    def request(verb, url, body, headers, symbolize_names: true)
      uri = URI(url)
      body = body ? StringIO.new(body.is_a?(Hash) ? JSON.dump(body) : body.to_s) : nil
      env = Rack::MockRequest.env_for(
        uri.to_s,
        (headers || {}).merge({
          'REQUEST_METHOD' => verb.to_s.upcase,
          'CONTENT_TYPE' => JSON_MIME,
          'HTTP_ACCEPT' => JSON_MIME,
          Rack::RACK_INPUT => body
        })
      )

      status, resp_headers, resp_body = @app.call(env)
      rresponse = Rack::Response.new(resp_body, status, resp_headers)
      resp_body = rresponse.body.each_with_object(+'') { |part, memo| memo << part }

      if rresponse.content_type == JSON_MIME && resp_body && !resp_body.empty?
        resp_body = JSON.parse(resp_body, symbolize_names:)
      end

      response = Net::HTTPResponse::CODE_TO_OBJ[status.to_s].new('1.1', status.to_s, '')
      rresponse.headers.each { |k, v| response[k] = v }
      response.instance_variable_set(:@read, true)
      response.body = resp_body
      response
    end
  end

end
