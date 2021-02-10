module RailsQuery
  class Filter
    TYPES = %i[equal contain gt lt range].freeze

    attr_reader :name, :type, :filter

    def initialize(name, options)
      @name = name

      if options.is_a?(Proc)
        @type = :proc
        @filter = options
      else
        type = options[:type]&.to_sym || :equal
        @type = TYPES.include?(type) ? type : :equal
        @field = options[:field]

        raise StandardError.new "Field :#{name} not found to apply filter" unless (@field)
      end
    end

    def apply(ar_query, val)
      if @type == :proc
        ar_query.instance_exec(val, &filter)
      else
        public_send("apply_#{@type}", ar_query, @field.path, val)
      end
    end

    def apply_equal(ar_query, path, val)
      ar_query.where(path => val)
    end

    def apply_contain(ar_query, path, val)
      ar_query.where("#{path} LIKE '%#{val}%'")
    end

    def apply_gt(ar_query, path, val)
      ar_query.where("#{path} > ?", val)
    end

    def apply_lt(ar_query, path, val)
      ar_query.where("#{path} < ?", val)
    end

    def apply_range(ar_query, path, val)
      ar_query.where(path => val.is_a?(Range) ? val : val[0]..val[1])
    end
  end
end
