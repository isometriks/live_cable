# frozen_string_literal: true

module Live
  class ChoreList < LiveCable::Component
    reactive :list, -> { 'home' }
    reactive :heading, -> { 'Chores' }

    reactive_query :chores, -> { Chore.where(list:).order(:id) } do |relation|
      relation.sort_by { |chore| chore.done ? 1 : 0 }
    end

    actions :switch_list, :rename, :add

    after_connect :watch_chores

    def summary
      "#{chores.count { |chore| !chore.done }} to do"
    end

    def switch_list(params)
      self.list = params[:list]
    end

    def rename(params)
      self.heading = params[:heading]
    end

    def add(params)
      Chore.create!(list:, name: params[:name])
      refresh(:chores)
    end

    private

    def watch_chores
      stream_from('chores', coder: ActiveSupport::JSON) do |data|
        if data['dirty']
          dirty(:chores)
        else
          refresh(*Array(data['refresh']).map(&:to_sym))
        end
      end
    end
  end
end
