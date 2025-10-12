# frozen_string_literal: true

require 'pathname'
require 'json'
require_relative 'smidge/version'
require_relative 'smidge/operation'
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

  def self.from_openapi(spec, http: HTTPAdapter.new, base_url: nil)
    spec_url = nil
    spec = case spec
    when URL_EXP
      spec_url = spec
      resp = http.get(spec_url, headers: Client::REQUEST_HEADERS, symbolize_names: false)
      raise MissingHTTPSpecError.new(resp) unless (200..299).cover?(resp.code.to_i)

      resp.body
    when Hash
      spec
    when READER_INTERFACE
      JSON.parse(spec.read)
    else
      raise ArgumentError, "Unhandled spec: #{spec}"
    end

    spec = Parser::OpenAPI.parse(spec)
    operations = Parser::BuildOperations.parse(spec)
    info = spec['info']
    base_url ||= find_base_url(spec, spec_url) 
    build_from(operations, info:).new(base_url:, http:)
  end

  def self.build_from(operations, info:)
    klass = Class.new(Client)
    klass.define_singleton_method(:name) do
      'Smidge::Client'
    end
    klass.info(info)
    operations.each do |op|
      klass.operation op
    end
    klass
  end

  def self.find_base_url(spec, spec_url)
    srv = spec['servers']&.first
    srv ? URI(srv['url']) : base_url_from_spec_url(spec_url)
  end

  def self.base_url_from_spec_url(spec_url)
    return nil unless spec_url

    URI(spec_url).tap do |url|
      url.path = ''
      url.query = nil
      url.fragment = nil
    end
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
