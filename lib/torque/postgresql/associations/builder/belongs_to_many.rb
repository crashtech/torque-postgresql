module Torque
  module PostgreSQL
    module Associations
      module Builder
        class BelongsToMany < ::ActiveRecord::Associations::Builder::CollectionAssociation
          def self.macro
            :belongs_to_many
          end

          def self.valid_options(options)
            super + [:touch, :optional, :default, :dependent, :primary_key, :required]
          end

          def self.valid_dependent_options
            [:restrict_with_error, :restrict_with_exception]
          end

          def self.define_callbacks(model, reflection)
            super
            add_touch_callbacks(model, reflection)   if reflection.options[:touch]
            add_default_callbacks(model, reflection) if reflection.options[:default]
          end

          def self.define_readers(mixin, name)
            mixin.class_eval <<-CODE, __FILE__, __LINE__ + 1
              def #{name}
                association(:#{name}).reader
              end
            CODE
          end

          def self.define_writers(mixin, name)
            mixin.class_eval <<-CODE, __FILE__, __LINE__ + 1
              def #{name}=(value)
                association(:#{name}).writer(value)
              end
            CODE
          end

          def self.add_default_callbacks(model, reflection)
            model.before_validation ->(o) do
              o.association(reflection.name).default(&reflection.options[:default])
            end
          end

          def self.add_touch_callbacks(model, reflection)
            foreign_key = reflection.foreign_key
            n           = reflection.name
            touch       = reflection.options[:touch]

            callback = ->(changes_method) do
              ->(record) do
                BelongsToMany.touch_record(record, record.send(changes_method), foreign_key,
                  n, touch, belongs_to_touch_method)
              end
            end

            unless reflection.counter_cache_column
              model.after_create callback.call(:saved_changes), if: :saved_changes?
              model.after_destroy callback.call(:changes_to_save)
            end

            model.after_update callback.call(:saved_changes), if: :saved_changes?
            model.after_touch callback.call(:changes_to_save)
          end

          def self.touch_record(o, changes, foreign_key, name, touch, touch_method) # :nodoc:
            old_foreign_ids = changes[foreign_key] && changes[foreign_key].first

            if old_foreign_ids.present?
              association = o.association(name)
              reflection = association.reflection
              klass = association.klass

              primary_key = reflection.association_primary_key(klass)
              old_records = klass.find_by(primary_key => old_foreign_ids)

              old_records&.map do |old_record|
                if touch != true
                  old_record.send(touch_method, touch)
                else
                  old_record.send(touch_method)
                end
              end
            end

            o.send(name)&.map do |record|
              if record && record.persisted?
                if touch != true
                  record.send(touch_method, touch)
                else
                  record.send(touch_method)
                end
              end
            end
          end

          def self.define_validations(model, reflection)
            if reflection.options.key?(:required)
              reflection.options[:optional] = !reflection.options.delete(:required)
            end

            if reflection.options[:optional].nil?
              required = model.belongs_to_many_required_by_default
            else
              required = !reflection.options[:optional]
            end

            super

            if required
              model.validates_presence_of reflection.name, message: :required
            end
          end
        end

        ::ActiveRecord::Associations::Builder.const_set(:BelongsToMany, BelongsToMany)
      end
    end
  end
end
