# frozen_string_literal: true

ENV['RBS_TEST_TARGET'] ||= 'Torque::PostgreSQL::*,Torque::Generators::*'
ENV['RBS_TEST_SKIP'] ||= '::Torque::PostgreSQL::Attributes::Lazy,::Torque::PostgreSQL::Adapter::OID::Range::Comparison'
ENV['RBS_TEST_OPT'] ||= '-I sig'
ENV['RBS_TEST_LOGLEVEL'] ||= 'warn'

require 'rbs/test/setup'
