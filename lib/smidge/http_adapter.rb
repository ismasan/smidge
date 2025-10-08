# frozen_string_literal: true

require 'net/http'

module Smidge
  class HTTPAdapter
    def initialize(verify_ssl: true)
      @verify_ssl = verify_ssl
    end

    def get(url, body: nil, headers: nil, symbolize_names: true)
      request(Net::HTTP::Get, url, body, headers, symbolize_names:)
    end

    def put(url, body: nil, headers: nil)
      request(Net::HTTP::Put, url, body, headers)
    end

    def post(url, body: nil, headers: nil)
      request(Net::HTTP::Post, url, body, headers)
    end

    def patch(url, body: nil, headers: nil)
      request(Net::HTTP::Patch, url, body, headers)
    end

    def delete(url, body: nil, headers: nil)
      request(Net::HTTP::Delete, url, body, headers)
    end

    private

    def request(klass, url, body, headers, symbolize_names: true)
      uri = URI(url)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"
      http.verify_mode = OpenSSL::SSL::VERIFY_NONE unless @verify_ssl

      req = klass.new(uri)
      apply_headers(req, headers)
      set_body(req, body)

      res = http.request(req)
      if res.content_type == 'application/json' && res.body
        res.body = JSON.new(res.read_body, symbolize_names:)
      end

      res
    end

    def apply_headers(req, headers)
      (headers || {}).each do |key, value|
        req[key] = value
      end
    end

    def set_body(req, body)
      return if !body || body.empty?

      if body.is_a?(Hash)
        req["Content-Type"] ||= "application/json"
        req.body = JSON.dump(body)
      else
        req.body = body.to_s
      end
    end
  end

end
