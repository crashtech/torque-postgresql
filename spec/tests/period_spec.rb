require 'spec_helper'

# TODO: Convert to shared examples
RSpec.describe 'Period' do
  let(:model) { Class.new(TimeKeeper) }
  let(:instance) { model.new }
  let(:fields) { %i[available period tzperiod] }
  let(:method_names) { Torque::PostgreSQL::config.period.method_names }
  let(:attribute_klass) { Torque::PostgreSQL::Attributes::Period }

  let(:true_value) { 'TRUE' }
  let(:false_value) { 'FALSE' }

  let(:klass_methods_range) { (0..22) }
  let(:instance_methods_range) { (23..29) }

  let(:klass_method_names) { method_names.to_a[klass_methods_range].to_h }
  let(:instance_method_names) { method_names.to_a[instance_methods_range].to_h }

  before { Time.zone = 'UTC' }

  def decorate(model, field, options = {})
    attribute_klass.include_on(model, :period_for)
    model.period_for(field, **options)
  end

  context 'on config' do
    let(:direct_method_names) do
      list = method_names.dup
      list.merge!(Torque::PostgreSQL::config.period.direct_method_names)
      list.values.map { |v| v.gsub(/_?%s_?/, '') }
    end

    let(:other_method_names) do
      method_names.transform_values.with_index { |_, idx| "p__#{idx}" }
    end

    it 'has definition method on the model' do
      attribute_klass.include_on(ActiveRecord::Base, :period_for)
      expect(model).to respond_to(:period_for)
      ActiveRecord::Base.singleton_class.send(:undef_method, :period_for)
    end

    it 'create the methods with custom names' do
      decorate(model, :tzperiod, threshold: 5.minutes, methods: other_method_names)

      klass_method_names.size.times do |i|
        expect(model).to respond_to("p__#{i}")
      end

      initial = instance_methods_range.min
      instance_method_names.size.times do |i|
        expect(instance).to respond_to("p__#{initial + i}")
      end
    end

    it 'creates non prefixed methods if requested' do
      decorate(model, :tzperiod, prefixed: false, threshold: 5.minutes)

      direct_method_names[klass_methods_range].each do |m|
        expect(model).to respond_to(m)
      end

      direct_method_names[instance_methods_range].each do |m|
        expect(instance).to respond_to(m)
      end
    end
  end

  context 'on tsrange' do
    let(:type) { :tsrange }
    let(:value) { Time.zone.now.beginning_of_minute }
    let(:db_field) { '"time_keepers"."period"' }
    let(:db_value) { "'#{value.strftime('%F %T')}'" }

    let(:cast_type) { '::timestamp' }
    let(:cast_db_value) { "#{db_value}#{cast_type}" }
    let(:empty_condition) { "#{type.to_s.upcase}(NULL, NULL)" }
    let(:nullif_condition) { "NULLIF(#{db_field}, #{empty_condition})" }

    let(:date_type) { :daterange }
    let(:lower_date) { "LOWER(#{db_field})::date" }
    let(:upper_date) { "UPPER(#{db_field})::date" }
    let(:date_db_field) { "#{date_type.to_s.upcase}(#{lower_date}, #{upper_date}, '[]')" }

    context 'on model' do
      before { decorate(model, :period) }

      it 'queries current on period' do
        expect(model.period_on(value).to_sql).to include(<<-SQL.squish)
          COALESCE(#{nullif_condition} @> #{cast_db_value}, #{true_value})
        SQL
      end

      it 'queries current period' do
        expect(model.current_period.to_sql).to include(<<-SQL.squish)
          COALESCE(#{nullif_condition} @>
        SQL

        expect(model.current_period.to_sql).to include(<<-SQL.squish)
          #{cast_type}, #{true_value})
        SQL
      end

      it 'queries not current period' do
        expect(model.not_current_period.to_sql).to include(<<-SQL.squish)
          NOT (COALESCE(#{nullif_condition} @>
        SQL

        expect(model.not_current_period.to_sql).to include(<<-SQL.squish)
          #{cast_type}, #{true_value})
        SQL
      end

      it 'queries containing period' do
        expect(model.period_containing(:test).to_sql).to include(<<-SQL.squish)
          #{db_field} @> "time_keepers"."test"
        SQL

        expect(model.period_containing(value).to_sql).to include(<<-SQL.squish)
          #{db_field} @> #{db_value}
        SQL
      end

      it 'queries not containing period' do
        expect(model.period_not_containing(:test).to_sql).to include(<<-SQL.squish)
          NOT (#{db_field} @> "time_keepers"."test")
        SQL

        expect(model.period_not_containing(value).to_sql).to include(<<-SQL.squish)
          NOT (#{db_field} @> #{db_value})
        SQL
      end

      it 'queries overlapping period' do
        expect(model.period_overlapping(:test).to_sql).to include(<<-SQL.squish)
          #{db_field} && "time_keepers"."test"
        SQL

        expect(model.period_overlapping(value, value).to_sql).to include(<<-SQL.squish)
          #{db_field} && #{type.to_s.upcase}(#{db_value}, #{db_value})
        SQL
      end

      it 'queries not overlapping period' do
        expect(model.period_not_overlapping(:test).to_sql).to include(<<-SQL.squish)
          NOT (#{db_field} && "time_keepers"."test")
        SQL

        expect(model.period_not_overlapping(value, value).to_sql).to include(<<-SQL.squish)
          NOT (#{db_field} && #{type.to_s.upcase}(#{db_value}, #{db_value}))
        SQL
      end

      it 'queries starting after period' do
        expect(model.period_starting_after(:test).to_sql).to include(<<-SQL.squish)
          LOWER(#{db_field}) > "time_keepers"."test"
        SQL

        expect(model.period_starting_after(value).to_sql).to include(<<-SQL.squish)
          LOWER(#{db_field}) > #{db_value}
        SQL
      end

      it 'queries starting before period' do
        expect(model.period_starting_before(:test).to_sql).to include(<<-SQL.squish)
          LOWER(#{db_field}) < "time_keepers"."test"
        SQL

        expect(model.period_starting_before(value).to_sql).to include(<<-SQL.squish)
          LOWER(#{db_field}) < #{db_value}
        SQL
      end

      it 'queries finishing after period' do
        expect(model.period_finishing_after(:test).to_sql).to include(<<-SQL.squish)
          UPPER(#{db_field}) > "time_keepers"."test"
        SQL

        expect(model.period_finishing_after(value).to_sql).to include(<<-SQL.squish)
          UPPER(#{db_field}) > #{db_value}
        SQL
      end

      it 'queries finishing before period' do
        expect(model.period_finishing_before(:test).to_sql).to include(<<-SQL.squish)
          UPPER(#{db_field}) < "time_keepers"."test"
        SQL

        expect(model.period_finishing_before(value).to_sql).to include(<<-SQL.squish)
          UPPER(#{db_field}) < #{db_value}
        SQL
      end

      it 'does not have real starting after for period' do
        expect(model.all).not_to respond_to(:real_starting_after)
      end

      it 'does not have real starting before for period' do
        expect(model.all).not_to respond_to(:real_starting_before)
      end

      it 'does not have real finishing after for period' do
        expect(model.all).not_to respond_to(:real_finishing_after)
      end

      it 'does not have real finishing before for period' do
        expect(model.all).not_to respond_to(:real_finishing_before)
      end

      it 'queries containing date period' do
        expect(model.period_containing_date(:test).to_sql).to include(<<-SQL.squish)
          #{date_db_field} @> "time_keepers"."test"
        SQL

        expect(model.period_containing_date(value).to_sql).to include(<<-SQL.squish)
          #{date_db_field} @> #{db_value}::date
        SQL
      end

      it 'queries not containing date period' do
        expect(model.period_not_containing_date(:test).to_sql).to include(<<-SQL.squish)
          NOT (#{date_db_field} @> "time_keepers"."test")
        SQL

        expect(model.period_not_containing_date(value).to_sql).to include(<<-SQL.squish)
          NOT (#{date_db_field} @> #{db_value}::date)
        SQL
      end

      it 'queries overlapping date period' do
        expect(model.period_overlapping_date(:test).to_sql).to include(<<-SQL.squish)
          #{date_db_field} && "time_keepers"."test"
        SQL

        expect(model.period_overlapping_date(value, value).to_sql).to include(<<-SQL.squish)
          #{date_db_field} && #{date_type.to_s.upcase}(#{db_value}::date, #{db_value}::date)
        SQL
      end

      it 'queries not overlapping date period' do
        expect(model.period_not_overlapping_date(:test).to_sql).to include(<<-SQL.squish)
          NOT (#{date_db_field} && "time_keepers"."test")
        SQL

        expect(model.period_not_overlapping_date(value, value).to_sql).to include(<<-SQL.squish)
          NOT (#{date_db_field} && #{date_type.to_s.upcase}(#{db_value}::date, #{db_value}::date))
        SQL
      end

      it 'does not have real containing date period' do
        expect(model.all).not_to respond_to(:period_real_containing_date)
      end

      it 'does not have real overlapping date period' do
        expect(model.all).not_to respond_to(:period_real_overlapping_date)
      end
    end

    context 'on instance' do
      before { decorate(model, :period) }

      it 'checks for current value' do
        instance.period = 1.hour.ago.utc..1.hour.from_now.utc
        expect(instance).to be_current_period

        instance.period = 4.hour.from_now.utc..6.hour.from_now.utc
        expect(instance).not_to be_current_period

        instance.period = [nil, 4.hours.ago.utc]
        expect(instance).not_to be_current_period

        instance.period = [4.hours.from_now.utc, nil]
        expect(instance).not_to be_current_period

        instance.period = [nil, nil]
        expect(instance).to be_current_period
      end

      it 'checks fro current based on a value' do
        instance.period = 1.hour.ago.utc..1.hour.from_now.utc
        expect(instance).to be_current_period_on(5.minutes.from_now.utc)

        instance.period = 4.hour.from_now.utc..6.hour.from_now.utc
        expect(instance).not_to be_current_period_on(5.minutes.from_now.utc)
      end

      it 'returns the start time' do
        instance.period = 1.hour.ago.utc..1.hour.from_now.utc
        expect(instance.period_start).to be_eql(instance.period.min)

        instance.period = 4.hour.from_now.utc..6.hour.from_now.utc
        expect(instance.period_start).to be_eql(instance.period.min)
      end

      it 'returns the finish time' do
        instance.period = 1.hour.ago.utc..1.hour.from_now.utc
        expect(instance.period_finish).to be_eql(instance.period.max)

        instance.period = 4.hour.from_now.utc..6.hour.from_now.utc
        expect(instance.period_finish).to be_eql(instance.period.max)
      end
    end

    context 'with field threshold' do
      before { decorate(model, :period, threshold: :th) }

      let(:lower_db_field) { "(LOWER(#{db_field}) - #{threshold_value})" }
      let(:upper_db_field) { "(UPPER(#{db_field}) + #{threshold_value})" }
      let(:threshold_value) { '"time_keepers"."th"' }
      let(:threshold_db_field) { "#{type.to_s.upcase}(#{lower_db_field}, #{upper_db_field})" }
      let(:nullif_condition) { "NULLIF(#{threshold_db_field}, #{empty_condition})" }
      let(:threshold_date_db_field) do
        "DATERANGE(#{lower_db_field}::date, #{upper_db_field}::date, '[]')"
      end

      context 'on model' do
        it 'queries current on period' do
          expect(model.period_on(value).to_sql).to include(<<-SQL.squish)
            COALESCE(#{nullif_condition} @> #{cast_db_value}, #{true_value})
          SQL
        end

        it 'queries current period' do
          expect(model.current_period.to_sql).to include(<<-SQL.squish)
            COALESCE(#{nullif_condition} @>
          SQL

          expect(model.current_period.to_sql).to include(<<-SQL.squish)
            #{cast_type}, #{true_value})
          SQL
        end

        it 'queries not current period' do
          expect(model.not_current_period.to_sql).to include(<<-SQL.squish)
            NOT (COALESCE(#{nullif_condition} @>
          SQL

          expect(model.not_current_period.to_sql).to include(<<-SQL.squish)
            #{cast_type}, #{true_value})
          SQL
        end

        it 'queries real containing period' do
          expect(model.period_real_containing(:test).to_sql).to include(<<-SQL.squish)
            #{threshold_db_field} @> "time_keepers"."test"
          SQL

          expect(model.period_real_containing(value).to_sql).to include(<<-SQL.squish)
            #{threshold_db_field} @> #{db_value}
          SQL
        end

        it 'queries real overlapping period' do
          expect(model.period_real_overlapping(:test).to_sql).to include(<<-SQL.squish)
            #{threshold_db_field} && "time_keepers"."test"
          SQL

          expect(model.period_real_overlapping(value, value).to_sql).to include(<<-SQL.squish)
            #{threshold_db_field} && #{type.to_s.upcase}(#{db_value}, #{db_value})
          SQL
        end

        it 'queries real starting after for period' do
          expect(model.period_real_starting_after(:test).to_sql).to include(<<-SQL.squish)
            #{lower_db_field} > "time_keepers"."test"
          SQL

          expect(model.period_real_starting_after(value).to_sql).to include(<<-SQL.squish)
            #{lower_db_field} > #{db_value}
          SQL
        end

        it 'queries real starting before for period' do
          expect(model.period_real_starting_before(:test).to_sql).to include(<<-SQL.squish)
            #{lower_db_field} < "time_keepers"."test"
          SQL

          expect(model.period_real_starting_before(value).to_sql).to include(<<-SQL.squish)
            #{lower_db_field} < #{db_value}
          SQL
        end

        it 'queries real finishing after for period' do
          expect(model.period_real_finishing_after(:test).to_sql).to include(<<-SQL.squish)
            #{upper_db_field} > "time_keepers"."test"
          SQL

          expect(model.period_real_finishing_after(value).to_sql).to include(<<-SQL.squish)
            #{upper_db_field} > #{db_value}
          SQL
        end

        it 'queries real finishing before for period' do
          expect(model.period_real_finishing_before(:test).to_sql).to include(<<-SQL.squish)
            #{upper_db_field} < "time_keepers"."test"
          SQL

          expect(model.period_real_finishing_before(value).to_sql).to include(<<-SQL.squish)
            #{upper_db_field} < #{db_value}
          SQL
        end

        it 'queries containing date period' do
          expect(model.period_containing_date(:test).to_sql).to include(<<-SQL.squish)
            #{date_db_field} @> "time_keepers"."test"
          SQL

          expect(model.period_containing_date(value).to_sql).to include(<<-SQL.squish)
            #{date_db_field} @> #{db_value}::date
          SQL
        end

        it 'queries not containing date period' do
          expect(model.period_not_containing_date(:test).to_sql).to include(<<-SQL.squish)
            NOT (#{date_db_field} @> "time_keepers"."test")
          SQL

          expect(model.period_not_containing_date(value).to_sql).to include(<<-SQL.squish)
            NOT (#{date_db_field} @> #{db_value}::date)
          SQL
        end

        it 'queries overlapping date period' do
          expect(model.period_overlapping_date(:test).to_sql).to include(<<-SQL.squish)
            #{date_db_field} && "time_keepers"."test"
          SQL

          expect(model.period_overlapping_date(value, value).to_sql).to include(<<-SQL.squish)
            #{date_db_field} && #{date_type.to_s.upcase}(#{db_value}::date, #{db_value}::date)
          SQL
        end

        it 'queries not overlapping date period' do
          expect(model.period_not_overlapping_date(:test).to_sql).to include(<<-SQL.squish)
            NOT (#{date_db_field} && "time_keepers"."test")
          SQL

          expect(model.period_not_overlapping_date(value, value).to_sql).to include(<<-SQL.squish)
            NOT (#{date_db_field} && #{date_type.to_s.upcase}(#{db_value}::date, #{db_value}::date))
          SQL
        end

        it 'queries real containing date period' do
          expect(model.period_real_containing_date(:test).to_sql).to include(<<-SQL.squish)
            #{threshold_date_db_field} @> "time_keepers"."test"
          SQL

          expect(model.period_real_containing_date(value).to_sql).to include(<<-SQL.squish)
            #{threshold_date_db_field} @> #{db_value}::date
          SQL
        end

        it 'queries real overlapping date period' do
          expect(model.period_real_overlapping_date(:test).to_sql).to include(<<-SQL.squish)
            #{threshold_date_db_field} && "time_keepers"."test"
          SQL

          expect(model.period_real_overlapping_date(value, value).to_sql).to include(<<-SQL.squish)
            #{threshold_date_db_field} && #{date_type.to_s.upcase}(#{db_value}::date, #{db_value}::date)
          SQL
        end
      end

      context 'on instance' do
        before { decorate(model, :period, threshold: :th) }
        before { instance.th = 1.hour }

        it 'checks for current value' do
          instance.period = nil
          expect(instance).to be_current_period

          instance.period = (Time.zone.now - 1.hour)..(Time.zone.now + 1.hour)
          expect(instance).to be_current_period

          instance.period = (Time.zone.now + 90.minutes)..(Time.zone.now + 3.hour)
          expect(instance).not_to be_current_period
        end

        it 'checks for current based on a value' do
          instance.period = nil
          expect(instance).to be_current_period_on(5.minutes.from_now.utc)

          instance.period = (Time.zone.now - 1.hour)..(Time.zone.now + 1.hour)
          expect(instance).to be_current_period_on(5.minutes.from_now.utc)

          instance.period = 90.minutes.from_now.utc..3.hour.from_now.utc
          expect(instance).not_to be_current_period_on(5.minutes.from_now.utc)
        end

        it 'returns the real range' do
          value = (Time.zone.now - 1.hour)..(Time.zone.now + 1.hour)
          instance.period = value
          expect(instance.real_period.min).to be_eql(value.min - 1.hour)
          expect(instance.real_period.max).to be_eql(value.max + 1.hour)
        end

        it 'returns the real start' do
          value = (Time.zone.now - 1.hour)..(Time.zone.now + 1.hour)
          instance.period = value
          expect(instance.period_real_start).to be_eql(value.min - 1.hour)
        end

        it 'returns the real finish' do
          value = (Time.zone.now - 1.hour)..(Time.zone.now + 1.hour)
          instance.period = value
          expect(instance.period_real_finish).to be_eql(value.max + 1.hour)
        end
      end
    end

    context 'with value threshold' do
      before { decorate(model, :period, threshold: 5.minutes) }

      let(:lower_db_field) { "(LOWER(#{db_field}) - #{threshold_value})" }
      let(:upper_db_field) { "(UPPER(#{db_field}) + #{threshold_value})" }
      let(:threshold_value) { "'300 seconds'::interval" }
      let(:threshold_db_field) { "#{type.to_s.upcase}(#{lower_db_field}, #{upper_db_field})" }
      let(:nullif_condition) { "NULLIF(#{threshold_db_field}, #{empty_condition})" }

      context 'on model' do
        it 'queries current on period' do
          expect(model.period_on(value).to_sql).to include(<<-SQL.squish)
            COALESCE(#{nullif_condition} @> #{cast_db_value}, #{true_value})
          SQL
        end

        it 'queries current period' do
          expect(model.current_period.to_sql).to include(<<-SQL.squish)
            COALESCE(#{nullif_condition} @>
          SQL

          expect(model.current_period.to_sql).to include(<<-SQL.squish)
            #{cast_type}, #{true_value})
          SQL
        end

        it 'queries not current period' do
          expect(model.not_current_period.to_sql).to include(<<-SQL.squish)
            NOT (COALESCE(#{nullif_condition} @>
          SQL

          expect(model.not_current_period.to_sql).to include(<<-SQL.squish)
            #{cast_type}, #{true_value})
          SQL
        end

        it 'queries real containing period' do
          expect(model.period_real_containing(:test).to_sql).to include(<<-SQL.squish)
            #{threshold_db_field} @> "time_keepers"."test"
          SQL

          expect(model.period_real_containing(value).to_sql).to include(<<-SQL.squish)
            #{threshold_db_field} @> #{db_value}
          SQL
        end

        it 'queries real overlapping period' do
          expect(model.period_real_overlapping(:test).to_sql).to include(<<-SQL.squish)
            #{threshold_db_field} && "time_keepers"."test"
          SQL

          expect(model.period_real_overlapping(value, value).to_sql).to include(<<-SQL.squish)
            #{threshold_db_field} && #{type.to_s.upcase}(#{db_value}, #{db_value})
          SQL
        end

        it 'queries real starting after for period' do
          expect(model.period_real_starting_after(:test).to_sql).to include(<<-SQL.squish)
            #{lower_db_field} > "time_keepers"."test"
          SQL

          expect(model.period_real_starting_after(value).to_sql).to include(<<-SQL.squish)
            #{lower_db_field} > #{db_value}
          SQL
        end

        it 'queries real starting before for period' do
          expect(model.period_real_starting_before(:test).to_sql).to include(<<-SQL.squish)
            #{lower_db_field} < "time_keepers"."test"
          SQL

          expect(model.period_real_starting_before(value).to_sql).to include(<<-SQL.squish)
            #{lower_db_field} < #{db_value}
          SQL
        end

        it 'queries real finishing after for period' do
          expect(model.period_real_finishing_after(:test).to_sql).to include(<<-SQL.squish)
            #{upper_db_field} > "time_keepers"."test"
          SQL

          expect(model.period_real_finishing_after(value).to_sql).to include(<<-SQL.squish)
            #{upper_db_field} > #{db_value}
          SQL
        end

        it 'queries real finishing before for period' do
          expect(model.period_real_finishing_before(:test).to_sql).to include(<<-SQL.squish)
            #{upper_db_field} < "time_keepers"."test"
          SQL

          expect(model.period_real_finishing_before(value).to_sql).to include(<<-SQL.squish)
            #{upper_db_field} < #{db_value}
          SQL
        end

        it 'queries containing date period' do
          expect(model.period_containing_date(:test).to_sql).to include(<<-SQL.squish)
            #{date_db_field} @> "time_keepers"."test"
          SQL

          expect(model.period_containing_date(value).to_sql).to include(<<-SQL.squish)
            #{date_db_field} @> #{db_value}
          SQL
        end

        it 'queries not containing date period' do
          expect(model.period_not_containing_date(:test).to_sql).to include(<<-SQL.squish)
            NOT (#{date_db_field} @> "time_keepers"."test")
          SQL

          expect(model.period_not_containing_date(value).to_sql).to include(<<-SQL.squish)
            NOT (#{date_db_field} @> #{db_value}::date)
          SQL
        end

        it 'queries overlapping date period' do
          expect(model.period_overlapping_date(:test).to_sql).to include(<<-SQL.squish)
            #{date_db_field} && "time_keepers"."test"
          SQL

          expect(model.period_overlapping_date(value, value).to_sql).to include(<<-SQL.squish)
            #{date_db_field} && #{date_type.to_s.upcase}(#{db_value}::date, #{db_value}::date)
          SQL
        end

        it 'queries not overlapping date period' do
          expect(model.period_not_overlapping_date(:test).to_sql).to include(<<-SQL.squish)
            NOT (#{date_db_field} && "time_keepers"."test")
          SQL

          expect(model.period_not_overlapping_date(value, value).to_sql).to include(<<-SQL.squish)
            NOT (#{date_db_field} && #{date_type.to_s.upcase}(#{db_value}::date, #{db_value}::date))
          SQL
        end
      end

      context 'on instance' do
        before { decorate(model, :period, threshold: 45.minutes) }

        it 'checks for current value' do
          instance.period = nil
          expect(instance).to be_current_period

          instance.period = (Time.zone.now - 1.hour)..(Time.zone.now + 1.hour)
          expect(instance).to be_current_period

          instance.period = (Time.zone.now + 90.minutes)..(Time.zone.now + 3.hour)
          expect(instance).not_to be_current_period
        end

        it 'checks for current based on a value' do
          instance.period = nil
          expect(instance).to be_current_period_on(5.minutes.from_now.utc)

          instance.period = (Time.zone.now - 1.hour)..(Time.zone.now + 1.hour)
          expect(instance).to be_current_period_on(5.minutes.from_now.utc)

          instance.period = 90.minutes.from_now.utc..3.hour.from_now.utc
          expect(instance).not_to be_current_period_on(5.minutes.from_now.utc)
        end

        it 'returns the real range' do
          value = (Time.zone.now - 1.hour)..(Time.zone.now + 1.hour)
          instance.period = value
          expect(instance.real_period.min).to be_eql(value.min - 45.minutes)
          expect(instance.real_period.max).to be_eql(value.max + 45.minutes)
        end

        it 'returns the real start' do
          value = (Time.zone.now - 1.hour)..(Time.zone.now + 1.hour)
          instance.period = value
          expect(instance.period_real_start).to be_eql(value.min - 45.minutes)
        end

        it 'returns the real finish' do
          value = (Time.zone.now - 1.hour)..(Time.zone.now + 1.hour)
          instance.period = value
          expect(instance.period_real_finish).to be_eql(value.max + 45.minutes)
        end
      end
    end
  end

  context 'on daterange' do
    let(:type) { :daterange }
    let(:value) { Date.today }
    let(:db_field) { '"time_keepers"."available"' }
    let(:db_value) { "'#{value.strftime('%F')}'" }

    let(:cast_type) { '::date' }
    let(:cast_db_value) { "#{db_value}#{cast_type}" }
    let(:empty_condition) { "#{type.to_s.upcase}(NULL, NULL)" }
    let(:nullif_condition) { "NULLIF(#{threshold_db_field}, #{empty_condition})" }

    let(:lower_db_field) { "(LOWER(#{db_field}) - #{threshold_value})::date" }
    let(:upper_db_field) { "(UPPER(#{db_field}) + #{threshold_value})::date" }
    let(:threshold_value) { "'86400 seconds'::interval" }
    let(:threshold_db_field) { "#{type.to_s.upcase}(#{lower_db_field}, #{upper_db_field})" }

    before { decorate(model, :available, pessimistic: true, threshold: 1.day) }

    context 'on model' do
      it 'queries current on available' do
        expect(model.available_on(value).to_sql).to include(<<-SQL.squish)
          COALESCE(#{nullif_condition} @> #{cast_db_value}, #{false_value})
        SQL
      end

      it 'queries current available' do
        expect(model.current_available.to_sql).to include(<<-SQL.squish)
          COALESCE(#{nullif_condition} @>
        SQL

        expect(model.current_available.to_sql).to include(<<-SQL.squish)
          #{cast_type}, #{false_value})
        SQL
      end

      it 'queries not current available' do
        expect(model.not_current_available.to_sql).to include(<<-SQL.squish)
          NOT (COALESCE(#{nullif_condition} @>
        SQL

        expect(model.not_current_available.to_sql).to include(<<-SQL.squish)
          #{cast_type}, #{false_value})
        SQL
      end

      it 'queries containing available' do
        expect(model.available_containing(:test).to_sql).to include(<<-SQL.squish)
          #{db_field} @> "time_keepers"."test"
        SQL

        expect(model.available_containing(value).to_sql).to include(<<-SQL.squish)
          #{db_field} @> #{db_value}
        SQL
      end

      it 'queries not containing available' do
        expect(model.available_not_containing(:test).to_sql).to include(<<-SQL.squish)
          NOT (#{db_field} @> "time_keepers"."test")
        SQL

        expect(model.available_not_containing(value).to_sql).to include(<<-SQL.squish)
          NOT (#{db_field} @> #{db_value})
        SQL
      end

      it 'queries overlapping available' do
        expect(model.available_overlapping(:test).to_sql).to include(<<-SQL.squish)
          #{db_field} && "time_keepers"."test"
        SQL

        expect(model.available_overlapping(value, value).to_sql).to include(<<-SQL.squish)
          #{db_field} && #{type.to_s.upcase}(#{db_value}, #{db_value})
        SQL
      end

      it 'queries not overlapping available' do
        expect(model.available_not_overlapping(:test).to_sql).to include(<<-SQL.squish)
          NOT (#{db_field} && "time_keepers"."test")
        SQL

        expect(model.available_not_overlapping(value, value).to_sql).to include(<<-SQL.squish)
          NOT (#{db_field} && #{type.to_s.upcase}(#{db_value}, #{db_value}))
        SQL
      end

      it 'queries starting after available' do
        expect(model.available_starting_after(:test).to_sql).to include(<<-SQL.squish)
          LOWER(#{db_field}) > "time_keepers"."test"
        SQL

        expect(model.available_starting_after(value).to_sql).to include(<<-SQL.squish)
          LOWER(#{db_field}) > #{db_value}
        SQL
      end

      it 'queries starting before available' do
        expect(model.available_starting_before(:test).to_sql).to include(<<-SQL.squish)
          LOWER(#{db_field}) < "time_keepers"."test"
        SQL

        expect(model.available_starting_before(value).to_sql).to include(<<-SQL.squish)
          LOWER(#{db_field}) < #{db_value}
        SQL
      end

      it 'queries finishing after available' do
        expect(model.available_finishing_after(:test).to_sql).to include(<<-SQL.squish)
          UPPER(#{db_field}) > "time_keepers"."test"
        SQL

        expect(model.available_finishing_after(value).to_sql).to include(<<-SQL.squish)
          UPPER(#{db_field}) > #{db_value}
        SQL
      end

      it 'queries finishing before available' do
        expect(model.available_finishing_before(:test).to_sql).to include(<<-SQL.squish)
          UPPER(#{db_field}) < "time_keepers"."test"
        SQL

        expect(model.available_finishing_before(value).to_sql).to include(<<-SQL.squish)
          UPPER(#{db_field}) < #{db_value}
        SQL
      end

      it 'queries real containing available' do
        expect(model.available_real_containing(:test).to_sql).to include(<<-SQL.squish)
          #{threshold_db_field} @> "time_keepers"."test"
        SQL

        expect(model.available_real_containing(value).to_sql).to include(<<-SQL.squish)
          #{threshold_db_field} @> #{db_value}
        SQL
      end

      it 'queries real overlapping available' do
        expect(model.available_real_overlapping(:test).to_sql).to include(<<-SQL.squish)
          #{threshold_db_field} && "time_keepers"."test"
        SQL

        expect(model.available_real_overlapping(value, value).to_sql).to include(<<-SQL.squish)
          #{threshold_db_field} && #{type.to_s.upcase}(#{db_value}, #{db_value})
        SQL
      end

      it 'queries real starting after for available' do
        expect(model.available_real_starting_after(:test).to_sql).to include(<<-SQL.squish)
          #{lower_db_field} > "time_keepers"."test"
        SQL

        expect(model.available_real_starting_after(value).to_sql).to include(<<-SQL.squish)
          #{lower_db_field} > #{db_value}
        SQL
      end

      it 'queries real starting before for available' do
        expect(model.available_real_starting_before(:test).to_sql).to include(<<-SQL.squish)
          #{lower_db_field} < "time_keepers"."test"
        SQL

        expect(model.available_real_starting_before(value).to_sql).to include(<<-SQL.squish)
          #{lower_db_field} < #{db_value}
        SQL
      end

      it 'queries real finishing after for available' do
        expect(model.available_real_finishing_after(:test).to_sql).to include(<<-SQL.squish)
          #{upper_db_field} > "time_keepers"."test"
        SQL

        expect(model.available_real_finishing_after(value).to_sql).to include(<<-SQL.squish)
          #{upper_db_field} > #{db_value}
        SQL
      end

      it 'queries real finishing before for available' do
        expect(model.available_real_finishing_before(:test).to_sql).to include(<<-SQL.squish)
          #{upper_db_field} < "time_keepers"."test"
        SQL

        expect(model.available_real_finishing_before(value).to_sql).to include(<<-SQL.squish)
          #{upper_db_field} < #{db_value}
        SQL
      end

      it 'does not query containing date available' do
        expect(model.all).not_to respond_to(:available_containing_date)
      end

      it 'does not query not containing date available' do
        expect(model.all).not_to respond_to(:available_not_containing_date)
      end

      it 'does not query overlapping date available' do
        expect(model.all).not_to respond_to(:available_overlapping_date)
      end

      it 'does not query not overlapping date available' do
        expect(model.all).not_to respond_to(:available_not_overlapping_date)
      end

      it 'does not query real containing date available' do
        expect(model.all).not_to respond_to(:available_real_containing_date)
      end

      it 'does not query real overlapping date available' do
        expect(model.all).not_to respond_to(:available_real_overlapping_date)
      end
    end

    context 'on instance' do
      it 'checks for current value' do
        instance.available = nil
        expect(instance).not_to be_current_available

        instance.available = Date.yesterday..Date.tomorrow
        expect(instance).to be_current_available

        instance.available = Date.new.prev_month..Date.new.next_month
        expect(instance).not_to be_current_available
      end

      it 'checks fro current based on a value' do
        instance.available = nil
        expect(instance).not_to be_current_available_on(Date.tomorrow)

        instance.available = Date.yesterday..Date.tomorrow
        expect(instance).to be_current_available_on(Date.tomorrow)

        instance.available = Date.new.prev_month..Date.new.next_month
        expect(instance).to be_current_available_on(Date.new.next_month)
      end

      it 'returns the start date' do
        instance.available = Date.yesterday..Date.tomorrow
        expect(instance.available_start).to be_eql(instance.available.min)

        instance.available = Date.new.prev_month..Date.new.next_month
        expect(instance.available_start).to be_eql(instance.available.min)
      end

      it 'returns the finish date' do
        instance.available = Date.yesterday..Date.tomorrow
        expect(instance.available_finish).to be_eql(instance.available.max)

        instance.available = Date.new.prev_month..Date.new.next_month
        expect(instance.available_finish).to be_eql(instance.available.max)
      end

      it 'returns the real range' do
        value = Date.yesterday..Date.tomorrow
        instance.available = value
        expect(instance.real_available.min).to be_eql(value.min.prev_day)
        expect(instance.real_available.max).to be_eql(value.max.next_day)
      end

      it 'returns the real start date' do
        instance.available = Date.yesterday..Date.tomorrow
        expect(instance.available_real_start).to be_eql(instance.available.min.prev_day)
      end

      it 'returns the real finish date' do
        instance.available = Date.yesterday..Date.tomorrow
        expect(instance.available_real_finish).to be_eql(instance.available.max.next_day)
      end
    end
  end
end
