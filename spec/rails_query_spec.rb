# frozen_string_literal: true
require 'spec_helper'

RSpec.describe RailsQuery do
  before do
    stub_const('RegionQuery', Class.new(RailsQuery::Query) do
      base_query Region

      field :name
    end)

    stub_const('UserQuery', Class.new(RailsQuery::Query) do
      base_query User.select(:name)

      field :name
      field :lastname
      field :age
      field :region_id

      field :fullname do |query|
        query.select("name || ' ' || lastname as fullname")
      end

      # field :event_vs_user_event_id, join: :events_vs_users, column: 'event_id'

      field :event_ids do |query|
        query.joins(:events_vs_users).select('events_vs_users.event_id as event_ids')
      end

      # field :event_count, join: :events_vs_users,
      #                     select: 'COUNT(events_vs_users.event_id)',
      #                     group: true

      field :event_count do |query|
        query.joins(:events_vs_users)
             .select('COUNT(events_vs_users.event_id) as event_count')
             .group(:id)
      end

      # field :event_points, join: {events_vs_users: :event},
      #                      select: 'SUM(events.points)',
      #                      group: true

      field :event_points do |query|
        query.joins(events_vs_users: :event)
             .select('SUM(events.points) as event_points')
             .group(:id)
      end

      # field :country_name, join: {region: :country}

      field :country_name do |query|
        query.joins(region: :country).select('countries.name as country_name')
      end

      # link_one :region, query: RegionQuery, key: :region_id

      field(:region,
        as_json: {include: {region: {only: %i[id name]}}}
      ) do |query|
        query.select(:region_id).includes(:region)
      end

      filter :under_age do |query, _val|
        query.where(age: 1..17)
      end

      filter :age_gt, operator: :gt, field: :age
      filter :age_lt, operator: :lt, field: :age
      filter :age_range, operator: :range, field: :age

      def as_json(query)
        options = {}

        if @query_fields.include?(:region)
          options.merge!(include: {region: {only: %i[id name]}})
        end

        query.as_json(options)
      end
    end)

    stub_const('EventQuery', Class.new(RailsQuery::Query) do
      base_query Event

      field :name
      field :date
      # field :event_type_name, join: :event_type
      # field :type_name, join: :event_type, table: 'event_types', column: 'name'

      # link_many :users, query: UserQuery, key: :event_vs_user_event_id
    end)
  end

  before :all do
    country_1 = Country.create!(name: 'Spain')
    country_2 = Country.create!(name: 'France')
    region_1 = Region.create!(name: 'Andalucía', country: country_1)
    region_2 = Region.create!(name: 'Picardy', country: country_2)

    @user_1 = User.create!(name: 'A', lastname: 'AA', age: 16, region: region_1)
    @user_2 = User.create!(name: 'B', lastname: 'BB', age: 60, region: region_2)

    type_1 = EventType.create!(name: 'Party')
    type_2 = EventType.create!(name: 'Meeting')

    @event_1 = Event.create!(name: 'Funny Event', event_type_id: type_1.id, points: 2)
    @event_2 = Event.create!(name: 'Boring Event', event_type_id: type_2.id, points: 2)

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
        {'id' => @user_1.id, 'name' => @user_1.name},
        {'id' => @user_2.id, 'name' => @user_2.name}
      ])

      expect(EventQuery.new.run).to eq([{'id' => 1}, {'id' => 2}])
    end

    it 'runs with simple fields' do
      expect(UserQuery.new(fields: %i[lastname age]).run).to eq(
        [@user_1, @user_2].map do |u|
          {id: u.id, name: u.name, lastname: u.lastname, age: u.age}.stringify_keys
        end
      )
    end

    it 'runs with custom fields' do
      expect(UserQuery.new(fields: [:fullname]).run).to eq(
        [@user_1, @user_2].map do |u|
          {id: u.id, name: u.name, fullname: "#{u.name} #{u.lastname}"}.stringify_keys
        end
      )
    end

    it 'runs with joined fields' do
      expect(UserQuery.new(fields: %i[country_name]).run).to eq(
        [@user_1, @user_2].map do |u|
          {id: u.id, name: u.name, country_name: u.region.country.name}.stringify_keys
        end
      )
    end

    it 'runs with agregate fields' do
      expect(UserQuery.new(fields: %i[event_count event_points]).run).to eq(
        [@user_1, @user_2].map do |u|
          {
            id: u.id,
            name: u.name,
            event_count: u.events_vs_users.size,
            event_points: u.events_vs_users.sum { |x| x.event.points }
          }.stringify_keys
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

    it 'runs with include field using belongs_to' do
      expect(UserQuery.new(fields: %i[region]).run).to eq(
        [@user_1, @user_2].map do |u|
          {
            'id' => u.id,
            'name' => u.name,
            'region_id' => u.region.id,
            'region' => {'id' => u.region.id, 'name' => u.region.name}
          }
        end
      )
    end

    it 'runs with filter of type :proc' do
      expect(UserQuery.new.filtrate(under_age: true).run).to eq([
        {'id' => @user_1.id, 'name' => @user_1.name}
      ])
    end

    it 'runs with filter of type :contains' do
      expect(UserQuery.new.filtrate(lastname: 'B').run).to eq([
        {'id' => @user_2.id, 'name' => @user_2.name}
      ])
    end

    it 'runs with filter of type :gt' do
      expect(UserQuery.new.filtrate(age_gt: 20).run).to eq([
        {'id' => @user_2.id, 'name' => @user_2.name}
      ])
    end

    it 'runs with filter of type :lt' do
      expect(UserQuery.new.filtrate(age_lt: 20).run).to eq([
        {'id' => @user_1.id, 'name' => @user_1.name}
      ])
    end

    it 'runs with filter of type :range' do
      expect(UserQuery.new.filtrate(age_range: [10, 20]).run).to eq([
        {'id' => @user_1.id, 'name' => @user_1.name}
      ])

      expect(UserQuery.new.filtrate(age_range: 30..100).run).to eq([
        {'id' => @user_2.id, 'name' => @user_2.name}
      ])
    end

    it 'runs with paginate' do
      expect(UserQuery.new.page(2).limit(1).run).to eq([
        {'id' => @user_2.id, 'name' => @user_2.name}
      ])
    end

    it 'runs with meta' do
      expect(UserQuery.new.page(2).limit(1).meta).to eq(
        {
          current_page: 2,
          total_pages: 2,
          total_count: 2,
          limit_value: 1,
          offset_value: 1
        }
      )
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
