# frozen_string_literal: true

module Torque
  module PostgreSQL
    module Adapter
      module OID
        # Moves a label path between the shapes the gem accepts, its pure list
        # of items and the text form PostgreSQL stores. Nothing is validated
        # here, that is left to PostgreSQL
        class Ltree < ActiveModel::Type::Value

          def type
            :ltree
          end

          def cast(value)
            return value if value.is_a?(value_class)
            return if value.blank?

            value_class.new(value)
          end

          def serialize(value)
            path = cast(value)
            path.map { |item| compile(item) }.join('.') unless path.nil?
          end

          def deserialize(value)
            return if value.nil?

            value_class.new(value, sanitize: false)
          end

          def items_for(value, sanitize: true)
            ::Array.wrap(value).flat_map { |entry| items_of(entry, sanitize) }
          end

          def type_cast_for_schema(value)
            serialize(value).inspect
          end

          def changed_in_place?(raw_old_value, new_value)
            raw_old_value != serialize(new_value)
          end

          def ==(other)
            other.class == self.class
          end
          alias eql? ==

          def hash
            self.class.hash
          end

          private

            def value_class
              LTree
            end

            def items_of(entry, sanitize)
              return items_for(LTree.compatible(entry), sanitize: sanitize) if LTree.compatible?(entry)

              case entry
              when LTree, LQuery then entry.items
              when ::Array then items_for(entry, sanitize: sanitize)
              when ::ActiveRecord::Base then labels_of(record_label(entry), sanitize)
              else labels_of(entry.to_s, sanitize)
              end
            end

            def labels_of(text, sanitize)
              text = sanitize(text) if sanitize
              text.split('.').map { |item| parse(item) }
            end

            def record_label(record)
              id = record.id
              raise ArgumentError, <<~MSG.squish if id.nil?
                Unable to use #{record.class.name} as a label because its
                #{record.class.primary_key} is still empty.
              MSG

              raise ArgumentError, <<~MSG.squish if id.is_a?(::Array)
                Unable to use #{record.class.name} as a label because it has a
                composite primary key, which cannot be a single label.
              MSG

              id.to_s
            end

            def sanitize(text)
              replacements = PostgreSQL.config.ltree.sanitize
              return text if replacements.blank?

              text.gsub(Regexp.union(replacements.keys), replacements)
            end

            def compile(item)
              item.to_s
            end

            def parse(text)
              text
            end

        end
      end
    end
  end
end
