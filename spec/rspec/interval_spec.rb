require 'spec_helper'

RSpec.describe 'Interval', type: :feature do
  let(:connection) { ActiveRecord::Base.connection }

  context 'on settings' do
    it 'must be set to ISO 8601' do
      expect(connection.select_value('SHOW IntervalStyle')).to eql('iso_8601')
    end
  end
end
