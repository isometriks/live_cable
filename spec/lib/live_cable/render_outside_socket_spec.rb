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

  it "says a connection identifier read on the page load isn't there because the component has no socket" do
    expect { Live::Counter.new('p').instance_eval { current_user } }.to raise_error(
      LiveCable::Error,
      "Live::Counter#current_user is an identifier of the ActionCable connection, and Live::Counter isn't " \
      'subscribed: it is rendering for the page load, or it has disconnected. Check `subscribed?`, and on the ' \
      'page load read it another way, such as from a Current attribute your controller sets'
    )
  end

  it 'still raises NameError for a name that is not a connection identifier' do
    expect { Live::Counter.new('n').instance_eval { current_admin } }.to raise_error(NameError, /current_admin/)
  end
end
