require 'spec_helper'

RSpec.describe 'Composite Types' do

  it "can save and load composite types" do
    start = DateTime.now.utc
    instance = Nested.new

    instance.nested = NestedStruct.new
    instance.nested.ary = [InnerStruct.new, InnerStruct.new]

    instance.nested.ary[0].num = 2
    instance.nested.ary[0].num_ary = [3]
    instance.nested.ary[0].str = "string contents"
    instance.nested.ary[0].str_ary = ["string array contents", '", with quotes and commas,"']
    instance.nested.ary[0].timestamp = start
    instance.nested.ary[0].timestamp_ary = [start + 1.minute, start + 2.minutes]
    instance.nested.ary[0].hsh = {"foo" => "bar"}
    instance.nested.ary[0].json = [nil, {sym: 4}]
    instance.save!
    instance = Nested.find(instance.id)

    expect(instance.nested.ary.length).to eq(2)
    expect(instance.nested.ary[0].num).to eq(2)
    expect(instance.nested.ary[0].num_ary).to eq([3])
    expect(instance.nested.ary[0].str).to eq("string contents")
    expect(instance.nested.ary[0].str_ary).to eq(["string array contents", '", with quotes and commas,"'])
    expect(instance.nested.ary[0].timestamp.to_i).to eq(start.to_i)
    expect(instance.nested.ary[0].timestamp_ary.map(&:to_i)).to eq([(start + 1.minute).to_i, (start + 2.minutes).to_i])
    expect(instance.nested.ary[0].hsh).to eq({"foo" => "bar"})
    expect(instance.nested.ary[0].json).to eq([nil, {"sym" => 4}])
  end
end
