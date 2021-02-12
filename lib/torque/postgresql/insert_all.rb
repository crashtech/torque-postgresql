# frozen_string_literal: true

module Torque
  module PostgreSQL
    module InsertAll
      attr_reader :where

      def initialize(*args, where: nil, **xargs)
        super(*args, **xargs)

        @where = where
      end
    end

    module InsertAll::Builder
      delegate :where, to: :insert_all

      def where_condition?
        !where.nil?
      end
    end

    ActiveRecord::InsertAll.prepend InsertAll
    ActiveRecord::InsertAll::Builder.include InsertAll::Builder
  end
end
