# frozen_string_literal: true

module LiveCable
  # Signs and verifies the reactive-variable defaults that travel from a
  # server-rendered page to the client and back on subscribe.
  #
  # Defaults originate on the server in the `live(...)` helper, but they are
  # emitted into the DOM as a `live-defaults` attribute and re-sent by the
  # client when its ActionCable subscription connects. Because that value
  # round-trips through the browser, it cannot be trusted: without signing, a
  # user could edit the attribute (or craft the subscribe frame) to set *any*
  # reactive variable at subscribe time - including ones deliberately not
  # marked `writable:`, such as a record id, price, or tenant key.
  #
  # The blob is signed with the application's secret_key_base and bound to the
  # component's live_id, so a tampered or replayed value verifies as invalid
  # and is treated as no defaults at all.
  module DefaultsSigner
    PURPOSE = 'live_cable/defaults'

    module_function

    # @param defaults [Hash] The reactive-variable defaults to sign
    # @param live_id [String] The component instance the defaults belong to
    # @return [String] A signed, tamper-evident blob
    def sign(defaults, live_id)
      verifier.generate({ 'live_id' => live_id, 'defaults' => defaults || {} }, purpose: PURPOSE)
    end

    # @param blob [String, nil] A blob previously produced by {sign}
    # @param live_id [String] The component instance the blob must be bound to
    # @return [Hash] The verified defaults, or an empty hash when the blob is
    #   blank, tampered with, or bound to a different component
    def verify(blob, live_id)
      return {} if blob.blank?

      data = verifier.verify(blob, purpose: PURPOSE)
      return {} unless data.is_a?(Hash) && data['live_id'] == live_id

      data['defaults'] || {}
    rescue ActiveSupport::MessageVerifier::InvalidSignature
      {}
    end

    # @return [ActiveSupport::MessageVerifier]
    def verifier
      # JSON serializer keeps the payload to simple, safe types (no Marshal).
      ActiveSupport::MessageVerifier.new(secret, serializer: JSON, url_safe: true)
    end

    def secret
      base = Rails.application.secret_key_base if defined?(Rails) && Rails.application
      raise LiveCable::Error, 'secret_key_base is required to sign LiveCable defaults' if base.blank?

      base
    end
  end
end
