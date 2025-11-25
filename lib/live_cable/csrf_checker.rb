# frozen_string_literal: true

module LiveCable
  class CsrfChecker
    include ActiveSupport::Configurable
    include ActionController::RequestForgeryProtection

    def initialize(request)
      @request = request
    end

    def valid?(session, token)
      valid_authenticity_token?(session, token)
    end

    private

    attr_reader :request
  end
end
