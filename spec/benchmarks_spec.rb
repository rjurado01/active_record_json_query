# frozen_string_literal: true
require 'spec_helper'
require 'benchmark'

# used to make tests
RSpec.describe 'Benchmarks' do
  before do
    stub_const('BenchmarkQuery', Class.new(RailsQuery::Query) do
      model User

      field :name, default: true

      field :country_name, join: {region: :country}
    end)
  end

  before :all do
    country = Country.create!(name: 'Spain')
    region = Region.create!(name: 'Andalucía', country: country)

    500.times do |n|
      User.create!(name: "Loop #{n}", lastname: 'AA', age: rand(16..90), region: region)
    end

    # ActiveRecord::Base.logger = Logger.new($stdout)
  end

  def compare(block_a, block_b)
    measure_1 = (Benchmark.measure do
      50.times { block_a.call }
    end)

    measure_2 = (Benchmark.measure do
      50.times { block_b.call }
    end)

    # p "#{measure_1.real} / #{measure_2.real}"
    expect(measure_1.real).to be < measure_2.real
  end

  xit 'is faster when use select' do
    compare(
      -> { BenchmarkQuery.new.select(:name).run },
      -> { User.select(:id, :name).to_a }
    )
  end

  xit 'is faster when use joined field' do
    compare(
      -> { BenchmarkQuery.new.select(:country_name).run },
      -> { User.joins(region: :country).select(:id, 'countries.name').to_a }
    )
  end
end
