# frozen_string_literal: true

class Chore < ActiveRecord::Base
  belongs_to :person, optional: true

  def self.create_tables
    ActiveRecord::Schema.define do
      suppress_messages do
        create_table(:people, force: true) { |t| t.string :name }

        create_table :chores, force: true do |t|
          t.string :name
          t.string :list, default: 'home'
          t.boolean :done, default: false
          t.references :person
          t.timestamps
        end
      end
    end
  end
end
