# frozen_string_literal: true

module LiveCable
  module Rendering
    class RenderResult
      # @return [String]
      attr_reader :live_id

      # @return [Array<String, nil>]
      attr_reader :parts

      # @return [String]
      attr_reader :template_hash

      # @return [Hash<String, RenderResult>]
      attr_accessor :child_results

      def initialize(live_id, parts, template_path)
        @live_id = live_id
        @parts = parts
        @template_hash = Digest::SHA256.hexdigest(template_path)[0..11]
        @child_results = {}
      end

      def empty?
        parts.compact.empty?
      end

      # True when this render changed nothing on the wire: no dynamic parts
      # were re-rendered and no child produced changes either. Used to skip
      # broadcasting a no-op refresh.
      def blank?
        empty? && child_results.values.all?(&:blank?)
      end

      def as_json
        {
          h: template_hash,
          p: parts,
          c: child_results.reject { |_k, v| v.empty? }.as_json,
        }.compact_blank
      end
    end
  end
end
