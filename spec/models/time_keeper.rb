class TimeKeeper < ActiveRecord::Base
  period_for :available, pessimistic: true, methods: {
    current:     :available,
    not_current: :unavailable,

    current?:    :available?,
    current_on?: :available_on?,
  }
end
