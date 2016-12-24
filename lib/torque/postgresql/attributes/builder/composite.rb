module Torque
  module PostgreSQL
    module Attributes
      module Builder
        class Composite

          LAZY_BUILDER = 'Torque::PostgreSQL::Attributes::Builder::Composite::LazyBuilder'

          attr_accessor :klass, :name, :relation

          # Start a new builder of methods for composite values on ActiveRecord::Base
          def initialize(klass, name, relation)
            @klass    = klass
            @name     = name
            @relation = relation.name
          end

          # Generate all methods needed
          def build
            reader
            writer
            builder
          end

          private

            # Define the reader method on klass to bring the relation
            def reader
              key = "'#{name}'"
              klass.module_eval <<-STR, __FILE__, __LINE__ + 1
                def #{name}
                  if @aggregation_cache.key?(#{key})
                    @aggregation_cache[#{key}]
                  elsif (values = _read_attribute(#{key})).nil?
                    @aggregation_cache[#{key}] = #{LAZY_BUILDER}.new(self, #{key})
                  else
                    build_#{name}(*values)
                  end
                end
              STR
            end

            # Define the writer method on klass to update the relation
            def writer
              key = "'#{name}'"
              klass.module_eval <<-STR, __FILE__, __LINE__ + 1
                def #{name}=(value)
                  case
                  when value.nil?
                    @aggregation_cache[#{key}] = #{LAZY_BUILDER}.new(self, #{key})
                    write_attribute_with_type_cast(#{key}, nil, false)
                  when @aggregation_cache[#{key}].nil?
                    build_#{name}(value)
                  else
                    relation = @aggregation_cache[#{key}]
                    relation.attributes = relation.class.cast_value(value)
                  end
                end
              STR
            end

            # Define the build so it can turn nil values into a relation
            def builder
              key = "'#{name}'"
              klass.module_eval <<-STR, __FILE__, __LINE__ + 1
                def build_#{name}(*args)
                  value = #{relation}.modelize(self, #{key}, args)
                  write_attribute_with_type_cast(#{key}, value, false)
                  @aggregation_cache[#{key}] = value
                end
              STR
            end

            # Only builds the relation if a method is called
            class LazyBuilder < Lazy

              def method_missing(name, *args, &block)
                @klass.send("build_#{@values[0]}").send(name, *args, &block)
              end

            end

        end
      end
    end
  end
end
