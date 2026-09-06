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

    # A masked token for the session behind the request - the value the page's
    # <meta name="csrf-token"> carries after a render
    #
    # @return [String]
    def token
      form_authenticity_token
    end

    private

    attr_reader :request
  end
end
