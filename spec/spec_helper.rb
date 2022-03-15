require 'bundler/setup'

require 'active_support'
require 'active_record'
require 'super_diff/rspec-rails'
require 'pry'

require 'rails_query'

ActiveRecord::Base.establish_connection(
  adapter: 'sqlite3', database: 'db/rails_query.sqlite3'
)

ActiveRecord::Base.connection.create_table(:countries, force: true) do |t|
  t.string :name
end

ActiveRecord::Base.connection.create_table(:regions, force: true) do |t|
  t.string :name
  t.belongs_to :country
end

ActiveRecord::Base.connection.create_table(:users, force: true) do |t|
  t.string :name
  t.string :lastname
  t.integer :age
  t.belongs_to :region
end

ActiveRecord::Base.connection.create_table(:events, force: true) do |t|
  t.string :name
  t.date :date
  t.integer :points
  t.belongs_to :event_type
end

ActiveRecord::Base.connection.create_table(:event_types, force: true) do |t|
  t.string :name
end

ActiveRecord::Base.connection.create_table(:events_vs_users, force: true) do |t|
  t.belongs_to :user
  t.belongs_to :event
end

class ApplicationRecord < ActiveRecord::Base
  self.abstract_class = true
end

class Country < ApplicationRecord
end

class Region < ApplicationRecord
  belongs_to :country
end

class User < ApplicationRecord
  belongs_to :region
  has_many :events_vs_users, class_name: 'EventVsUser'
end

class Event < ApplicationRecord
  belongs_to :event_type

  has_many :events_vs_users, class_name: 'EventVsUser'
  has_many :users, class_name: 'User', through: :events_vs_users
end

class EventType < ApplicationRecord
end

class EventVsUser < ApplicationRecord
  self.table_name = :events_vs_users

  belongs_to :user
  belongs_to :event
end

RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = '.rspec_status'

  # Disable RSpec exposing methods globally on `Module` and `main`
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  config.before :all do
    [EventVsUser, Event, User, Region, Country].each(&:destroy_all)
  end
end
