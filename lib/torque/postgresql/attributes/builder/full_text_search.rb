# frozen_string_literal: true

module Torque
  module PostgreSQL
    module Attributes
      module Builder
        class FullTextSearch
          attr_accessor :klass, :attribute, :options, :klass_module,
            :default_rank, :default_order, :default_language

          def initialize(klass, attribute, options = {})
            @klass = klass
            @attribute = attribute
            @options = options

            @default_rank = options[:with_rank] == true ? 'rank' : options[:with_rank]&.to_s

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
          #
          # def full_text_search(value, order: :asc, rank: :rank, language: 'english', phrase: true)
          #   attr = arel_table["search_vector"]
          #   binder = ->(prop, val) do
          #     attr_klass = ActiveRecord::Relation::QueryAttribute
          #     Arel::Nodes::BindParam.new(attr_klass.new(prop, val, attr.type_caster))
          #   end
          #
          #   lang = language.to_s if !language.is_a?(::Symbol)
          #   lang ||= arel_table[language.to_s].pg_cast(:regconfig) if has_attribute?(language)
          #   lang ||= public_send(language) if respond_to?(language)
          #
          #   raise ArgumentError, <<~MSG.squish if lang.nil?
          #     Unable to determine language from #{language.inspect}.
          #   MSG
          #
          #   value = binder.call(:value, value.to_s)
          #   lang = binder.call(:lang, lang) if lang.is_a?(::String)
          #
          #   function = phrase ? 'PHRASETO_TSQUERY' : 'TO_TSQUERY'
          #   query = Arel::Nodes::NamedFunction.new(function, [lang, value])
          #   ranker = Arel::Nodes::NamedFunction.new('TS_RANK', [attr, query]) if rank || order
          #
          #   result = where(Arel::Nodes::InfixOperation.new(:"@@", attr, query))
          #   result = result.order(ranker.public_send(order == :desc ? :desc : :asc)) if order
          #   result.select_extra_values += [ranker.as(rank == true ? 'rank' : rank.to_s)] if rank
          #   result
          # end
          def add_scope_to_module
            klass_module.module_eval <<-RUBY, __FILE__, __LINE__ + 1
              def #{scope_name}(value#{scope_args})
                attr = arel_table['#{attribute}']
                binder = ->(prop, val) do
                  attr_klass = ::ActiveRecord::Relation::QueryAttribute
                  ::Arel::Nodes::BindParam.new(attr_klass.new(prop, val, attr.type_caster))
                end

                lang = language.to_s if !language.is_a?(::Symbol)
                lang ||= arel_table[language.to_s] if has_attribute?(language)
                lang ||= public_send(language) if respond_to?(language)

                raise ::ArgumentError, <<~MSG.squish if lang.nil?
                  Unable to determine language from \#{language.inspect}.
                MSG

                value = binder.call(:value, value.to_s)
                lang = binder.call(:lang, lang) if lang.is_a?(::String)

                function = phrase ? 'PHRASETO_TSQUERY' : 'TO_TSQUERY'
                query = ::Arel::Nodes::NamedFunction.new(function, [lang, value])
                ranker = ::Arel::Nodes::NamedFunction.new('TS_RANK', [attr, query]) if rank || order

                result = where(::Arel::Nodes::InfixOperation.new(:"@@", attr, query))
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
            args << ", phrase: true"
            args
          end
        end
      end
    end
  end
end
