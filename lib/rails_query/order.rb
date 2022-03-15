module RailsQuery
  class Order
    DIRS = %i[asc desc].freeze

    attr_reader :name,
                :block

    def initialize(name, options, block)
      column = options[:column] || name

      @name = name.to_s
      @block = block || ->(query, dir) { query.order(column => dir) }
    end

    def apply(query, dir)
      dir = dir.downcase.to_sym

      return query unless DIRS.include?(dir)

      instance_exec(query, dir, &block)
    end
  end
end
