# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Rendering a component outside the socket' do
  it 'renders with Component#render when there is no connection' do
    expect(Live::Counter.new('x').render).to include('live-id="x"')
  end

  it 'renders a component instance from a controller' do
    expect(ApplicationController.render(Live::Counter.new('y'), layout: false)).to include('live-id="y"')
  end

  it "still gives component code Kernel's format" do
    price = 1.5

    expect(Live::Counter.new('z').instance_eval { format('%.2f', price) }).to eq('1.50')
  end
end
