module Brief
  class Model::Definition
    attr_accessor :type_alias,
                  :name,
                  :metadata_schema,
                  :content_schema,
                  :options,
                  :defined_helpers,
                  :section_mappings,
                  :template_body,
                  :example_body

    def initialize(name, options = {})
      @name             = name
      @options          = options
      @type_alias       = options.fetch(:type_alias) { name.downcase.parameterize.gsub(/-/, '_') }
      @metadata_schema  = {}.to_mash
      @section_mappings = {}.to_mash
      @content_schema   = { attributes: {} }.to_mash
      @model_class      = options[:model_class]
    end

    def valid?
      name.to_s.length > 0 && type_alias.to_s.length > 0
    end

    def validate!
      definition = self

      if valid?
        create_model_class.tap do |k|
          k.send(:include, Brief::Model)

          k.definition ||= definition

          k.name ||= name
          k.type_alias ||= type_alias

          Brief::Model.classes << k
        end

        apply_config
      end
    end

    def apply_config
      # define a virtus attribute mapping
      metadata_schema.values.each do |settings|
        begin
          settings[:args] = Array(settings[:args])
          settings[:args][1] = String if settings[:args][1] == ''
          model_class.send(:attribute, *(settings[:args]))
        rescue => e
          raise "Error in metadata schema definition.\n #{ settings.inspect } \n\n #{e.message}"
        end
      end

      # defined helpers adds an anonymous module include
      Array(defined_helpers).each { |mod| model_class.send(:include, mod) }

      model_class.defined_actions += Array(defined_actions)
      true
    end

    def create_model_class
      unless (model_namespace.const_get(type_alias.camelize) rescue nil)
        model_namespace.const_set(type_alias.camelize, Class.new)
      end
    end

    def model_class
      @model_class || model_namespace.const_get(type_alias.camelize) rescue Brief.default_model_class
    end

    def model_namespace
      Brief.configuration.model_namespace || Brief::Model
    end

    def meta(_options = {}, &block)
      @current = :meta
      instance_eval(&block)
    end

    def content(_options = {}, &block)
      @current = :content
      instance_eval(&block)
    end

    def example(body = nil, _options = {})
      if body.is_a?(Hash)
        options = body
      elsif body.is_a?(String)
        self.example_body = body
      end
    end

    def template(body = nil, _options = {})
      if body.is_a?(Hash)
        options = body
      elsif body.is_a?(String)
        self.template_body = body
      end
    end

    def has_actions?
      !@defined_actions.empty?
    end

    def actions(&block)
      helpers(&block)
    end

    def defined_actions
      Array(defined_helpers).map(&:instance_methods).flatten
    end

    def helpers(&block)
      self.defined_helpers ||= []

      if block
        mod = Module.new
        mod.module_eval(&block)

        self.defined_helpers << mod
      end
    end

    def inside_meta?
      @current == :meta
    end

    def inside_content?
      @current == :content
    end

    def section_mapping(identifier)
      section_mappings.fetch(identifier)
    end

    def method_missing(meth, *args, &block)
      args = args.dup

      if inside_content?
        if meth.to_sym == :define_section
          opts = args.extract_options!
          identifier = args.first
          section_mappings[identifier] ||= Brief::Document::Section::Mapping.new(identifier, opts)
          section_mapping(identifier).instance_eval(&block) if block
        else
          content_schema.attributes[meth] = { args: args, block: block }
        end
      elsif inside_meta?
        if args.first.is_a?(Hash)
          args.unshift(String)
        end
        args.unshift(meth)
        metadata_schema[meth] = { args: args, block: block }
      else
        super
      end
    end
  end
end
