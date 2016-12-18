require 'spec_helper'

RSpec.describe 'Config' do
  subject { Torque::Postgresql.config }
  it 'should have all settings as methods' do
    Torque::Postgresql::Config::SETTINGS.each do |setting|
      expect(subject).to respond_to(setting)
      expect(subject).to respond_to("#{setting}=")
    end
  end

  it 'should be able to run multiple times' do
    Torque::Postgresql.configure do |config|
      config.enum_initializer = false
    end

    expect(subject.enum_initializer).to be_falsey

    subject.enum_initializer = true
    expect(subject.enum_initializer).to be_truthy
  end
end
