require 'spec_helper'

RSpec.describe 'Data collector', type: :helper do
  let(:methods_list) { [:foo, :bar] }
  subject { Torque::PostgreSQL::Collector.new(*methods_list) }

  it 'is a class creator' do
    expect(subject).to be_a(Class)
  end

  it 'has the requested methods' do
    instance = subject.new
    methods_list.each do |name|
      expect(instance).to respond_to(name)
      expect(instance).to respond_to("#{name}=")
    end
  end

  it 'instace values starts as nil' do
    instance = subject.new
    methods_list.each do |name|
      expect(instance.send(name)).to be_nil
    end
  end

  it 'set values on the same method' do
    instance = subject.new
    methods_list.each do |name|
      expect(instance.send(name, name)).to eql(name)
    end
  end

  it 'get value on the same method' do
    instance = subject.new
    methods_list.each do |name|
      instance.send(name, name)
      expect(instance.send(name)).to eql(name)
    end
  end

  it 'accepts any kind of value' do
    instance = subject.new

    instance.foo 123
    expect(instance.foo).to eql(123)

    instance.foo 'chars'
    expect(instance.foo).to eql('chars')

    instance.foo :test, :test
    expect(instance.foo).to eql([:test, :test])

    instance.foo test: :test
    expect(instance.foo).to eql({test: :test})

    instance.foo nil
    expect(instance.foo).to be_nil
  end
end
