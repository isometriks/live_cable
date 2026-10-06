# frozen_string_literal: true

module LiveCable
  # Digests the values that identify who a page was rendered for, so the
  # client can tell when they change between pages without learning them.
  #
  # Keyed with a key derived from secret_key_base: a plain hash of a user id
  # could be matched by hashing guessed ids.
  module IdentityDigest
    PURPOSE = 'live_cable/identity'

    module_function

    # @param values [Array<Object>] Records are identified by their GlobalID,
    #   as ActionCable identifies a connection; anything else by its to_s
    # @return [String] A hex digest
    def digest(*values)
      payload = values.map { |value| value.respond_to?(:to_gid_param) ? value.to_gid_param : value.to_s }

      OpenSSL::HMAC.hexdigest('SHA256', key, JSON.generate(payload))
    end

    def key
      Rails.application.key_generator.generate_key(PURPOSE)
    end
  end
end
