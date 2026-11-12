# frozen_string_literal: true

module LiveCable
  module Rendering
    # Builds the controllers socket renders run on, on a request made from the
    # socket's own: its host, protocol, headers, cookies and session, under
    # the application's script name. It builds that request only once.
    class ControllerRenderer
      # What Rack and Rails memoize on the socket's request, and its body
      SOCKET_ONLY = /\A(?:
        action_dispatch\.(?:request\.|route(?:\z|_)|cookies\z) |
        action_controller\. |
        rack\.(?:request\.|hijack|input\z)
      )/x
      private_constant :SOCKET_ONLY

      # @return [Class]
      attr_reader :controller

      # @param controller [Class]
      # @param socket_request [ActionDispatch::Request]
      def initialize(controller, socket_request)
        @controller = controller
        @request = ActionDispatch::Request.new(env_for(socket_request))
        @response = controller.make_response!(@request)
      end

      # @return [ActionController::Base]
      def build_controller
        controller.new.tap do |instance|
          instance.set_request!(@request)
          instance.set_response!(@response)
        end
      end

      private

      def env_for(socket_request)
        env = socket_request.env.reject { |key, _| SOCKET_ONLY.match?(key) }
        env.except!('CONTENT_LENGTH', 'CONTENT_TYPE', 'ORIGINAL_FULLPATH', 'REQUEST_PATH', 'REQUEST_URI')
        env.merge!(
          'REQUEST_METHOD' => 'GET',
          'SCRIPT_NAME' => env['ORIGINAL_SCRIPT_NAME'].to_s,
          'PATH_INFO' => '',
          'QUERY_STRING' => '',
          'HTTP_ACCEPT' => Mime[:html].to_s,
          'rack.input' => StringIO.new,
          'action_dispatch.routes' => controller._routes
        )
      end
    end
  end
end
