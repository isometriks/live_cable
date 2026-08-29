# frozen_string_literal: true

module LiveCable
  module Rendering
    # Builds controllers as ActionController::Renderer#render does, but on one
    # request and response it keeps, so a connection builds those only once.
    class ControllerRenderer < ActionController::Renderer
      # @param controller_class [Class]
      # @return [ControllerRenderer]
      def self.from_defaults(controller_class)
        self.for(controller_class, nil, controller_class.renderer.defaults)
      end

      def initialize(...)
        super
        @request = ActionDispatch::Request.new(env_for_request)
        @request.routes = controller._routes
        @response = controller.make_response!(@request)
      end

      # @return [ActionController::Base]
      def build_controller
        controller.new.tap do |instance|
          instance.set_request!(@request)
          instance.set_response!(@response)
        end
      end
    end
  end
end
