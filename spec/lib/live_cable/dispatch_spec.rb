# frozen_string_literal: true

require 'rails_helper'

RSpec.describe LiveCable::Dispatch do
  describe '#params' do
    def action_params(query) = described_class.from_message('_action' => 'save', 'params' => query).params.to_unsafe_h

    def request_params(query) = ActionDispatch::Request.new(Rack::MockRequest.env_for("/?#{query}")).params

    ['token[]', 'token[]&token[]=', 'user[token][]', 'user[name]=Ann&tags[]=a&tags[]=b'].each do |query|
      it "parses #{query} as a Rails request does" do
        expect(action_params(query)).to eq(request_params(query))
      end
    end

    it 'refuses a value that is not valid UTF-8, as a Rails request does' do
      expect { request_params('a=%ff') }.to raise_error(ActionController::BadRequest)
      expect { action_params('a=%ff') }.to raise_error(StandardError)
    end
  end
end
