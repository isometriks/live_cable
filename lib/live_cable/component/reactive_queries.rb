# frozen_string_literal: true

module LiveCable
  class Component
    module ReactiveQueries
      extend ActiveSupport::Concern

      Fingerprint = Data.define(:digest, :version) do
        def self.digest(relation)
          ActiveSupport::Digest.hexdigest(relation.to_sql)
        end

        def self.for(relation)
          new(digest(relation), relation.cache_key_with_version)
        end
      end

      included do
        class_attribute :reactive_queries, default: {}.freeze
      end

      class_methods do
        def reactive_query(name, scope, shared: nil, &transform)
          raise ArgumentError, "Query for :#{name} must be a proc" unless scope.is_a?(Proc)
          raise ArgumentError, 'reactive_query has no shared: option' unless shared.nil?

          self.reactive_queries = reactive_queries.merge(name => [scope, transform]).freeze

          define_method(name) { reactive_query_result(name) }
        end
      end

      def refresh(*names)
        raise LiveCable::Error, 'refresh cannot be called during a render' if @reactive_query_results

        names = self.class.reactive_queries.keys if names.empty?
        names.each { |name| reactive_query_definition(name) }
        return unless live_connection

        names.each do |name|
          fingerprint = Fingerprint.for(reactive_query_relation(name))
          next if fingerprint == stored_fingerprint(name)

          live_connection.store(live_id, name, fingerprint)
          dirty(name)
        end
      end

      def render_in(...)
        @reactive_query_results = {}
        check_reactive_query_digests if live_connection

        super
      ensure
        @reactive_query_results = nil
      end

      private

      def reactive_query_definition(name)
        self.class.reactive_queries.fetch(name) do
          raise LiveCable::Error, "Invalid reactive query: #{name}"
        end
      end

      def reactive_query_relation(name)
        relation = instance_exec(&reactive_query_definition(name).first)
        unless relation.is_a?(ActiveRecord::Relation)
          raise LiveCable::Error, "reactive_query :#{name} must return an ActiveRecord::Relation, got #{relation.class}"
        end
        unless relation.klass.column_names.include?('updated_at')
          raise LiveCable::Error, "reactive_query :#{name} needs an updated_at column on #{relation.klass.table_name}"
        end

        relation = relation.scope if relation.is_a?(ActiveRecord::Associations::CollectionProxy)
        relation.loaded? ? relation.dup : relation
      end

      def reactive_query_result(name)
        results = @reactive_query_results
        return results[name] if results&.key?(name)

        transform = reactive_query_definition(name).last
        relation = reactive_query_relation(name)
        result = transform ? instance_exec(relation, &transform) : relation.load
        return result unless results

        if live_connection
          relation = relation.dup unless fingerprinted_from_records?(relation)
          live_connection.store(live_id, name, Fingerprint.for(relation))
        end

        results[name] = result
      end

      # Rails counts a loaded relation's records, which only matches its SQL
      # COUNT(*) when each row is one record with its own updated_at.
      def fingerprinted_from_records?(relation)
        relation.loaded? && !relation.eager_loading? && relation.select_values.empty? &&
          relation.group_values.empty? && !relation.distinct_value
      end

      def stored_fingerprint(name)
        live_connection.get(live_id, self, name, nil)
      end

      def check_reactive_query_digests
        return if self.class.reactive_queries.empty? || live_connection.changeset_for(self).empty?

        self.class.reactive_queries.each_key do |name|
          stored = stored_fingerprint(name)
          next if stored.nil? || stored.digest == Fingerprint.digest(reactive_query_relation(name))

          dirty(name)
        end
      end
    end
  end
end
