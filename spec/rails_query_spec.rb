# frozen_string_literal: true
require 'spec_helper'

RSpec.describe RailsQuery do
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
  end

  class EventType < ApplicationRecord
  end

  class EventVsUser < ApplicationRecord
    self.table_name = :events_vs_users
  end

  class RegionQuery < RailsQuery::Query
    model Region

    field :name
  end

  class UserQuery < RailsQuery::Query
    model User

    field :name, default: true
    field :lastname
    field :age

    field :event_vs_user_event_id, join: :events_vs_users,
                                   column: 'event_id'

    field :country_name, join: {region: :country}

    field :region_id

    field :fullname, select: "name || ' ' || lastname"

    link_one :region, query: RegionQuery, key: :region_id

    method :now, ->(_row) { Time.new(2020).utc }

    filter :adult, ->(_val) { where(age: 1..17) }
  end

  class EventQuery < RailsQuery::Query
    model Event

    field :name
    field :date
    field :event_type_name, join: :event_type
    field :type_name, join: :event_type, table: 'event_types', column: 'name'

    link_many :users, query: UserQuery, key: :event_vs_user_event_id
  end

  class EventVsUserQuery < RailsQuery::Query
  end

  before :all do
    country_1 = Country.create!(name: 'Spain')
    country_2 = Country.create!(name: 'France')
    region_1 = Region.create!(name: 'Andalucía', country: country_1)
    region_2 = Region.create!(name: 'Picardy', country: country_2)

    @user_1 = User.create!(name: 'A', lastname: 'AA', age: 16, region: region_1)
    @user_2 = User.create!(name: 'B', lastname: 'BB', age: 60, region: region_2)
    # @user_3 = User.create!(name: 'C', lastname: 'CC', age: 60, region: region_2)

    type_1 = EventType.create!(name: 'Party')
    type_2 = EventType.create!(name: 'Meeting')

    @event_1 = Event.create!(name: 'Funny Event', event_type_id: type_1.id)
    @event_2 = Event.create!(name: 'Boring Event', event_type_id: type_2.id)

    EventVsUser.create(event_id: @event_1.id, user_id: @user_1.id)
    EventVsUser.create(event_id: @event_1.id, user_id: @user_2.id)
    EventVsUser.create(event_id: @event_2.id, user_id: @user_1.id)
  end

  it 'has a version number' do
    expect(RailsQuery::VERSION).not_to be nil
  end

  describe 'queries' do
    it 'runs default' do
      expect(UserQuery.new.run).to eq([
        {'id' => 1, 'name' => 'A'},
        {'id' => 2, 'name' => 'B'}
      ])

      expect(EventQuery.new.run).to eq([{'id' => 1}, {'id' => 2}])
    end

    it 'runs with select' do
      expect(UserQuery.new.select(:lastname, :age).run).to eq(
        [@user_1, @user_2].map do |u|
          {id: u.id, name: u.name, lastname: u.lastname, age: u.age}.stringify_keys
        end
      )
    end

    it 'runs with select using field with select option' do
      expect(UserQuery.new.select(:fullname).run).to eq(
        [@user_1, @user_2].map do |u|
          {id: u.id, name: u.name, fullname: "#{u.name} #{u.lastname}"}.stringify_keys
        end
      )
    end

    it 'runs with select using method' do
      expect(UserQuery.new.select(:now).run).to eq(
        [@user_1, @user_2].map do |u|
          {id: u.id, name: u.name, now: Time.new(2020).utc}.stringify_keys
        end
      )
    end

    it 'runs with select using joined field' do
      expect(EventQuery.new.select(:name, :event_type_name, :type_name).run).to eq(
        [@event_1, @event_2].map do |e|
          {
            id: e.id,
            name: e.name,
            event_type_name: e.event_type.name,
            type_name: e.event_type.name
          }.stringify_keys
        end
      )
    end

    it 'runs with select using 2 levels joined field' do
      expect(UserQuery.new.select(:country_name).run).to eq(
        [@user_1, @user_2].map do |u|
          {id: u.id, name: u.name, country_name: u.region.country.name}.stringify_keys
        end
      )
    end

    it 'runs with include using has_many link' do
      expect(EventQuery.new.include(users: [:lastname]).run).to eq(
        [
          {
            'id' => @event_1.id,
            'users' => [
              {'id' => @user_1.id, 'name' => @user_1.name, 'lastname' => @user_1.lastname},
              {'id' => @user_2.id, 'name' => @user_2.name, 'lastname' => @user_2.lastname}
            ]
          },
          {
            'id' => @event_2.id,
            'users' => [
              {'id' => @user_1.id, 'name' => @user_1.name, 'lastname' => @user_1.lastname}
            ]
          }
        ]
      )
    end

    it 'runs with include using belongs_to link' do
      expect(UserQuery.new.include(:region).run).to eq(
        [
          {
            'id' => @user_1.id,
            'name' => @user_1.name,
            'region' => {'id' => @user_1.region.id}
          },
          {
            'id' => @user_2.id,
            'name' => @user_2.name,
            'region' => {'id' => @user_2.region.id}
          }
        ]
      )
    end

    it 'runs with filter' do
      expect(UserQuery.new.filtrate(adult: true).run).to eq([
        {'id' => @user_1.id, 'name' => @user_1.name}
      ])
    end

    it 'runs with paginate' do
      expect(UserQuery.new.page(2).limit(1).run).to eq([
        {'id' => @user_2.id, 'name' => @user_2.name}
      ])
    end

    it 'runs with meta' do
      expect(UserQuery.new.page(2).limit(1).meta).to eq({
        current_page: 2,
        total_pages: 2,
        total_count: 2,
        limit_value: 1,
        offset_value: 1
      })
    end

    it 'runs with order' do
      expect(UserQuery.new.order(name: 'desc').run).to eq(
        [@user_2, @user_1].map do |u|
          {id: u.id, name: u.name}.stringify_keys
        end
      )
    end

    it 'runs with order by joined field' do
      expect(EventQuery.new.select(:event_type_name).order(event_type_name: 'asc').run).to eq(
        [@event_2, @event_1].map do |e|
          {id: e.id, event_type_name: e.event_type.name}.stringify_keys
        end
      )
    end
  end
end
