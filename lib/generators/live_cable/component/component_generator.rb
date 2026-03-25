# frozen_string_literal: true

module LiveCable
  module Generators
    class ComponentGenerator < Rails::Generators::NamedBase
      source_root File.expand_path('templates', __dir__)

      class_option :compound, type: :boolean, default: false,
        desc: 'Generate a compound component with a directory of templates'
      class_option :actions, type: :array, default: [],
        desc: 'Action methods to define on the component'
      class_option :reactive, type: :array, default: [],
        desc: 'Reactive variables to define (e.g., count:integer name:string items:array)'

      def create_component_file
        template 'component.rb.tt', File.join('app/live', class_path, "#{file_name}.rb")
      end

      def create_view_file
        if compound?
          template 'view.html.live.erb.tt',
            File.join('app/views/live', class_path, file_name, 'component.html.live.erb')
        else
          template 'view.html.live.erb.tt',
            File.join('app/views/live', class_path, "#{file_name}.html.live.erb")
        end
      end

      private

      def compound?
        options[:compound]
      end

      def reactive_variables
        options[:reactive].map do |attr|
          name, type = attr.split(':')
          [name, default_for_type(type)]
        end
      end

      def action_names
        options[:actions]
      end

      def default_for_type(type)
        case type&.downcase
        when 'integer', 'int'    then '0'
        when 'string', 'text'    then '""'
        when 'boolean', 'bool'   then 'false'
        when 'array'             then '[]'
        when 'hash'              then '{}'
        else                          'nil'
        end
      end
    end
  end
end
