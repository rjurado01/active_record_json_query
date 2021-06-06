# frozen_string_literal: true
require 'spec_helper'
require 'benchmark'

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

    50.times do |n|
      User.create!(name: "Loop #{n}", lastname: 'AA', age: rand(16..90), region: region)
    end
  end

  def compare(block_a, block_b)
    measure_1 = (Benchmark.measure do
      50.times { block_a.call.run.to_json }
    end)

    measure_2 = (Benchmark.measure do
      50.times { block_b.call.all.to_json }
    end)

    # p "#{measure_1.real} / #{measure_2.real}"
    expect(measure_1.real).to be < measure_2.real
  end

  it 'is faster when use select' do
    compare(
      -> { BenchmarkQuery.new.select(:name) },
      -> { User.select(:name) }
    )
  end

  it 'is faster when use joined field' do
    compare(
      -> { BenchmarkQuery.new.select(:country_name) },
      -> { User.joins(region: :country).select('countries.name') }
    )
  end
end
