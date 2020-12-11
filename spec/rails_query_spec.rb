# frozen_string_literal: true
require 'spec_helper'

RSpec.describe RailsQuery do
  class ApplicationRecord < ActiveRecord::Base
    self.abstract_class = true
  end

  class User < ApplicationRecord
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

  class UserQuery < RailsQuery::Query
    model User

    field :name, default: true
    field :lastname
    field :age

    field :event_vs_user_event_id, join: :events_vs_users,
                                   column: 'event_id'

    field :fullname, select: "name || ' ' || lastname"

    method :now, ->(_row) { Time.new(2020).utc }

    filter :adult, ->(_val) { where(age: 1..17) }
  end

  class EventQuery < RailsQuery::Query
    model Event

    field :name
    field :date
    field :event_type_name, join: :event_type
    field :type_name, join: :event_type, table: 'event_types', column: 'name'

    relation :users, query: UserQuery, through: :event_vs_user_event_id
  end

  before :all do
    @u1 = User.create!(name: 'A', lastname: 'AA', age: 16)
    @u2 = User.create!(name: 'B', lastname: 'BB', age: 60)

    t1 = EventType.create!(name: 'Party')
    t2 = EventType.create!(name: 'Meeting')

    @e1 = Event.create!(name: 'Funny Event', event_type_id: t1.id)
    @e2 = Event.create!(name: 'Boring Event', event_type_id: t2.id)

    EventVsUser.create(event_id: @e1.id, user_id: @u1.id)
    EventVsUser.create(event_id: @e1.id, user_id: @u2.id)
    EventVsUser.create(event_id: @e2.id, user_id: @u1.id)
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
        [@u1, @u2].map do |u|
          {id: u.id, name: u.name, lastname: u.lastname, age: u.age}.stringify_keys
        end
      )
    end

    it 'runs with select using field with select option' do
      expect(UserQuery.new.select(:fullname).run).to eq(
        [@u1, @u2].map do |u|
          {id: u.id, name: u.name, fullname: "#{u.name} #{u.lastname}"}.stringify_keys
        end
      )
    end

    it 'runs with select using method' do
      expect(UserQuery.new.select(:now).run).to eq(
        [@u1, @u2].map do |u|
          {id: u.id, name: u.name, now: Time.new(2020).utc}.stringify_keys
        end
      )
    end

    it 'runs with select using joined field' do
      expect(EventQuery.new.select(:event_type_name, :type_name).run).to eq(
        [@e1, @e2].map do |e|
          {
            id: e.id,
            event_type_name: e.event_type.name,
            type_name: e.event_type.name
          }.stringify_keys
        end
      )
    end

    it 'runs with include' do
      expect(EventQuery.new.include(:users).run).to eq(
        [
          {
            'id' => @e1.id,
            'users' => [
              {'id' => @u1.id, 'name' => @u1.name},
              {'id' => @u2.id, 'name' => @u2.name}
            ]
          },
          {
            'id' => @e2.id,
            'users'=> [
              {'id' => @u1.id, 'name' => @u1.name}
            ]
          }
        ]
      )
    end

    it 'runs with filter' do
      expect(UserQuery.new.filtrate(adult: true).run).to eq([
        {'id' => @u1.id, 'name' => @u1.name}
      ])
    end

    it 'runs with paginate' do
      expect(UserQuery.new.paginate(2, 1).run).to eq([
        {'id' => @u2.id, 'name' => @u2.name}
      ])
    end

    it 'runs with meta' do
      expect(UserQuery.new.paginate(2, 1).meta).to eq({
        current_page: 2,
        total_pages: 2,
        total_count: 2,
        limit_value: 1,
        offset_value: 1
      })
    end

    it 'runs with order' do
      expect(UserQuery.new.order(name: 'desc').run).to eq(
        [@u2, @u1].map do |u|
          {id: u.id, name: u.name}.stringify_keys
        end
      )
    end

    it 'runs with order by joined field' do
      expect(EventQuery.new.select(:event_type_name).order(event_type_name: 'asc').run).to eq(
        [@e2, @e1].map do |e|
          {id: e.id, event_type_name: e.event_type.name}.stringify_keys
        end
      )
    end
  end
end
