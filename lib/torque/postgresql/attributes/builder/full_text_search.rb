# frozen_string_literal: true

module Torque
  module PostgreSQL
    module Attributes
      module Builder
        class FullTextSearch
          attr_accessor :klass, :attribute, :options, :klass_module,
            :default_rank, :default_mode, :default_order, :default_language

          def initialize(klass, attribute, options = {})
            @klass = klass
            @attribute = attribute
            @options = options

            @default_rank = options[:with_rank] == true ? 'rank' : options[:with_rank]&.to_s
            @default_mode = options[:mode] || PostgreSQL.config.full_text_search.default_mode

            @default_order =
              case options[:order]
              when :asc, true then :asc
              when :desc then :desc
              else false
              end

            @default_language = options[:language] if options[:language].is_a?(String) ||
              options[:language].is_a?(Symbol)
            @default_language ||= PostgreSQL.config.full_text_search.default_language.to_s
          end

          # What is the name of the scope to be added to the model
          def scope_name
            @scope_name ||= [
              options[:prefix],
              :full_text_search,
              options[:suffix],
            ].compact.join('_')
          end

          # Just check if the scope name is already defined
          def conflicting?
            return if options[:force] == true

            if klass.dangerous_class_method?(scope_name)
              raise Interrupt, scope_name.to_s
            end
          end

          # Create the proper scope
          def build
            @klass_module = Module.new
            add_scope_to_module
            klass.extend klass_module
          end

          # Creates a class method as the scope that builds the full text search
          def add_scope_to_module
            klass_module.module_eval <<-RUBY, __FILE__, __LINE__ + 1
              def #{scope_name}(value#{scope_args})
                attr = arel_table['#{attribute}']
                fn = ::Torque::PostgreSQL::FN

                lang = language.to_s if !language.is_a?(::Symbol)
                lang ||= arel_table[language.to_s] if has_attribute?(language)
                lang ||= public_send(language) if respond_to?(language)

                function = {
                  default: :to_tsquery,
                  phrase: :phraseto_tsquery,
                  plain: :plainto_tsquery,
                  web: :websearch_to_tsquery,
                }[mode.to_sym]

                raise ::ArgumentError, <<~MSG.squish if lang.blank?
                  Unable to determine language from \#{language.inspect}.
                MSG

                raise ::ArgumentError, <<~MSG.squish if function.nil?
                  Invalid mode \#{mode.inspect} for full text search.
                MSG

                value = fn.bind(:value, value.to_s, attr.type_caster)
                lang = fn.bind(:lang, lang, attr.type_caster) if lang.is_a?(::String)

                query = fn.public_send(function, lang, value)
                ranker = fn.ts_rank(attr, query) if rank || order

                result = where(fn.infix(:"@@", attr, query))
                result = result.order(ranker.public_send(order == :desc ? :desc : :asc)) if order
                result.select_extra_values += [ranker.as(rank == true ? 'rank' : rank.to_s)] if rank
                result
              end
            RUBY
          end

          # Returns the arguments to be used on the scope
          def scope_args
            args = +''
            args << ", order: #{default_order.inspect}"
            args << ", rank: #{default_rank.inspect}"
            args << ", language: #{default_language.inspect}"
            args << ", mode: :#{default_mode}"
            args
          end
        end
      end
    end
  end
end
