# frozen_string_literal: true

require 'plumb'

module Smidge
  module Parser
    include Plumb::Types

    BLANK_ARRAY = [].freeze
    BLANK_HASH = {}.freeze
    BLANK_STRING = ''

    Description = (String | Nil.invoke(:to_s))

    ParameterNode = Hash[
      'name' => String,
      'in' => String.options(%w[query path header]),
      'description?' => Description,
      'example?' => String,
      'required' => Boolean.default(false),
      'schema' => Hash[
        'type' => String,
        'default?' => String,
        'enum?' => Array
      ].default({ 'type' => 'string' }.freeze),
    ]

    ArrayNode = Hash[
      'type' => 'array',
      'items' => Any
    ]

    ObjectNode = Hash[
      'type' => 'object',
      'required' => Array[String].default(BLANK_ARRAY),
      'properties' => Hash[String, Any.defer{ SchemaNode }].default(BLANK_HASH),
    ]

    Ref = String.transform(::Array) do |str|
      str.gsub(/^#\//, '').split('/')
    end

    RefNode = Hash['$ref' => Ref]
    
    ScalarNode = Hash[
      'type' => String,
      'description?' => Description,
      'example?' => Any,
      'nullable?' => Boolean,
      'format?' => String,
      'enum?' => Array,
    ]

    SchemaNode = ObjectNode | ArrayNode | ScalarNode | RefNode

    BodyContentTypeNode = Hash[
      'schema' => SchemaNode
    ]

    VerbNode = Hash[
      'summary?' => String,
      'operationId?' => String,
      'description?' => Description,
      'tags' => Array[String].default(BLANK_ARRAY),
      'parameters' => Array[ParameterNode].default(BLANK_ARRAY),
      'requestBody?' => Hash[
        'content' => Hash[String, BodyContentTypeNode].default(BLANK_HASH)
      ]
    ]

    PathNode = Hash[
      'get?' => VerbNode,
      'post?' => VerbNode,
      'put?' => VerbNode,
      'delete?' => VerbNode,
      'patch?' => VerbNode,
    ]

    # Server URLs can be paths, eg '/pets'
    # based on the SPEC's URL
    ServerNode = Hash['url' => String, 'description?' => Description]
    TagNode = Hash['name' => String, 'description?' => Description]

    SchemaResolver = proc do |r|
      paths = r.value['paths'].values
      paths.each do |path|
        path.each_value do |cnt|
          contents = (cnt.dig('requestBody', 'content') || BLANK_HASH).values
          contents.each do |content|
            schema = content['schema']
            if (ref = schema['$ref'])
              resolved = r.value.dig(*ref)
              content['schema'] = resolved if resolved
            end
          end
        end
      end

      r.value.delete('components')
      r.valid
    end

    OpenAPI = Hash[
      'openapi' => String,
      'info' => Hash[
        'title' => String.default(BLANK_STRING),
        'description?' => Description,
        'version?' => String
      ].default(BLANK_HASH),
      'servers' => Array[ServerNode].default(BLANK_ARRAY),
      'tags' => Array[TagNode].default(BLANK_ARRAY),
      'paths' => Hash[String, PathNode],
      'components' => Hash.default(BLANK_HASH)
    ] >> SchemaResolver

    PathsToTuples = proc do |r|
      ops = r.value.fetch('paths').each.with_object([]) do |(path, verbs), memo|
        verbs.each do |verb, details|
          memo << [path, verb, details]
        end
      end

      r.valid ops
    end

    class TupleToOperation
      ParamArray = Array[SymbolizedHash.build(Smidge::Operation::Param)]

      def self.call(result)
        path, verb, details = result.value

        name = details['operationId'].to_s.strip
        description = details['description'] || details['summary'] || ''
        parameters = ParamArray.parse(details['parameters'])
        bschema = details.dig('requestBody', 'content', 'application/json', 'schema') || {}
        required = (bschema['required'] || [])
        body_params = (bschema['properties'] || {}).map do |name, prop|
          attrs = { in: 'body', name:, required: required.include?(name)}.merge(SymbolizedHash.parse(prop))
          Smidge::Operation::Param.new(attrs)
        end

        parameters.concat(body_params)
        name = "#{verb}_#{path}" if name.empty?

        result.valid(Smidge::Operation.new(
          name: Smidge.to_method_name(name).to_sym, 
          verb: verb.to_sym, 
          path:, 
          description:, 
          parameters:
        ))
      end
    end

    BuildOperations = Hash.pipeline do |pl|
      pl.step PathsToTuples
      pl.step Array[TupleToOperation]
    end

    OpenAPIToOperations = OpenAPI >> BuildOperations
  end
end
