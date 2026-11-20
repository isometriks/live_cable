# frozen_string_literal: true

module Live
  class ActionArguments < LiveCable::Component
    Pager = Struct.new(:component) do
      def next_page = component.received << :next_page
    end

    reactive :received, -> { [] }

    actions :required, :optional, :splat, :optional_with_keywords, :keywords_only, :none,
      :next_page, :wrapped, :wrapped_with_params, :ghost

    delegate :next_page, to: :pager

    prepend(Module.new do
      def wrapped(*) = super
      def wrapped_with_params(*) = super
    end)

    def required(params)
      received << params[:q]
    end

    def optional(params = nil)
      received << params&.[](:q)
    end

    def splat(*args)
      received << args.first&.[](:q)
    end

    def optional_with_keywords(params = nil, **)
      received << params&.[](:q)
    end

    def keywords_only(**options)
      received << options
    end

    def none
      received << :none
    end

    def wrapped
      received << :wrapped
    end

    def wrapped_with_params(params)
      received << params[:q]
    end

    def method_missing(name, *args)
      name == :ghost ? received << args : super
    end

    def respond_to_missing?(name, include_private = false)
      name == :ghost || super
    end

    private

    def pager = Pager.new(self)
  end
end
