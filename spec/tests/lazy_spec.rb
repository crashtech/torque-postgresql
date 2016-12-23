require 'spec_helper'

RSpec.describe 'Lazy', type: :helper do
  subject { Torque::PostgreSQL::Attributes::Lazy }

  it 'is consider nil' do
    expect(subject.new(String, '')).to be_nil
  end

  it 'inspects as nil' do
    expect(subject.new(String, '').inspect).to be_eql('nil')
  end

  it 'compares to nil only' do
    expect(subject.new(String, '') == nil).to be_truthy
    expect(subject.new(String, '') == '').to be_falsey
    expect(subject.new(String, '') == 0).to be_falsey
  end

  it 'starts the object only on method call' do
    expect(subject.new(String, '').to_s).to be_a(String)
    expect(subject.new(String, '')).to respond_to(:chop)
  end
end
