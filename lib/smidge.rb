# frozen_string_literal: true

require 'pathname'
require 'json'
require_relative 'smidge/version'
require_relative 'smidge/parser'

module Smidge
  class Error < StandardError; end
  MissingSpecError = Class.new(Error)
  InvalidSpecError = Class.new(Error)

  class MissingHTTPSpecError < MissingSpecError
    attr_reader :response

    def initialize(response)
      @response = response
      super("Failed to fetch OpenAPI spec: HTTP #{response.code}")
    end
  end

  URL_EXP = /^http(s)?:\/\//
  READER_INTERFACE = Plumb::Types::Interface[:read]

  def self.from_openapi(spec_url, http: HTTPAdapter.new, base_url: nil)
    spec = case spec_url
    when URL_EXP
      resp = http.get(spec_url, headers: Client::REQUEST_HEADERS, symbolize_names: false)
      raise MissingHTTPSpecError.new(resp) unless (200..299).cover?(resp.code.to_i)

      resp.body
    when Hash
      spec_url
    when READER_INTERFACE
      JSON.parse(spec_url.read)
    else
      raise ArgumentError, "Unhandled spec: #{spec_url}"
    end

    spec = Parser::OpenAPI.parse(spec)
    Client.new(spec, http:, base_url: base_url)
  end

  def self.to_method_name(str)
    str.to_s
      .gsub(/([a-z\d])([A-Z])/, '\1_\2') # split camel case
      .gsub(/([A-Z]+)([A-Z][a-z])/, '\1_\2') # handle acronyms like "XMLParser"
      .gsub(/[^a-zA-Z0-9_]/, '_')        # replace non-ascii/non-word chars
      .downcase
      .sub(/\A[\d_]+/, '')               # remove leading digits/underscores
      .gsub(/_+/, '_')                   # collapse multiple underscores
      .sub(/_+\z/, '')
  end
end

require_relative 'smidge/client'
