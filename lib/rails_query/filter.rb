module RailsQuery
  class Filter
    OPERATORS = %i[equal contain gt lt range].freeze

    attr_reader :name, :operator, :block

    def initialize(name, options, block)
      @name = name

      if block
        @block = block
      else
        @operator = options[:operator]
        @column = options[:column] || name

        unless OPERATORS.include?(@operator)
          raise StandardError, "Filter #{name}: #{@operator} operator not supported"
        end
      end
    end

    def apply(query, val)
      if @block
        instance_exec(query, val, &block)
      else
        public_send("apply_#{@operator}", query, @column, val)
      end
    end

    def apply_equal(query, column, val)
      query.where(column => val)
    end

    def apply_contain(query, column, val)
      query.where("#{column} LIKE '%#{val}%'")
    end

    def apply_gt(query, column, val)
      query.where("#{column} > ?", val)
    end

    def apply_lt(query, column, val)
      query.where("#{column} < ?", val)
    end

    def apply_range(query, column, val)
      query.where(column => val.is_a?(Range) ? val : val[0]..val[1])
    end
  end
end
