module Torque
  module Range
    def intersection(other)
      raise ArgumentError, 'value must be a Range' unless other.kind_of?(Range)

      new_min = self.cover?(other.min) ? other.min : other.cover?(min) ? min : nil
      new_max = self.cover?(other.max) ? other.max : other.cover?(max) ? max : nil

      new_min && new_max ? new_min..new_max : nil
    end
    alias_method :&, :intersection

    def union(other)
      raise ArgumentError, 'value must be a Range' unless other.kind_of?(Range)

      ([min, other.min].min)..([max, other.max].max)
    end
    alias_method :|, :union
  end

  ::Range.include(Range)
end
