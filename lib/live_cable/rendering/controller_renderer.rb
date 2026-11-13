# frozen_string_literal: true

module LiveCable
  module Rendering
    # Builds the controllers socket renders run on, on a request made from the
    # socket's own: its host, protocol, headers, cookies and session, under
    # the application's script name, for the page the component is on. It
    # builds the env for each page only once, and every render a request,
    # response and flash of its own on a copy of it.
    class ControllerRenderer
      # What Rack and Rails memoize on the socket's request, and its body
      SOCKET_ONLY = /\A(?:
        action_dispatch\.(?:request\.|route(?:\z|_)|cookies\z) |
        action_controller\. |
        rack\.(?:request\.|hijack|input\z)
      )/x
      PAGE_PATH = %r{\A(/(?!/)[^?#]*)(?:\?([^#]*))?\z}
      KEPT_PAGES = 8
      private_constant :SOCKET_ONLY, :PAGE_PATH, :KEPT_PAGES

      # @return [Class]
      attr_reader :controller

      # @param controller [Class]
      # @param socket_request [ActionDispatch::Request]
      def initialize(controller, socket_request)
        @controller = controller
        @env = env_for(socket_request).freeze
        @pages = {}
      end

      # @param path [String, nil] the path and query of the page the component
      #   is on, as the client sent it
      # @return [ActionController::Base]
      def build_controller(path = nil)
        request = ActionDispatch::Request.new(page(path).dup)
        request.flash = ActionDispatch::Flash::FlashHash.new

        controller.new.tap do |instance|
          instance.set_request!(request)
          instance.set_response!(controller.make_response!(request))
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

      def page(path)
        @pages[path] ||= begin
          @pages.shift if @pages.size >= KEPT_PAGES
          page_env(path).freeze
        end
      end

      def page_env(path)
        script_name = @env['SCRIPT_NAME']
        page_path, query = PAGE_PATH.match(path.to_s)&.captures
        return @env unless page_path == script_name || page_path&.start_with?("#{script_name}/")

        path_info = page_path.delete_prefix(script_name).presence || '/'
        env = @env.merge('PATH_INFO' => path_info, 'QUERY_STRING' => query.to_s, 'ORIGINAL_FULLPATH' => path)
        env.merge!(ActionDispatch::Http::Parameters::PARAMETERS_KEY => recognize(env).freeze)
      end

      def recognize(env)
        request = ActionDispatch::Request.new(env.dup)
        controller._routes.recognize_path_with_request(request, request.path_info, {})
      # A route constraint can raise or throw, as Devise's authenticate does
      # for a socket with no one signed in
      rescue StandardError
        {}
      end
    end
  end
end
