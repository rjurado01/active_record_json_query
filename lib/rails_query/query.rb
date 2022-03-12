module RailsQuery
  class Query
    @base_query = nil

    class << self
      def inherited(child)
        super

        child.instance_variable_set(:@fields, {})
        child.instance_variable_set(:@filters, {})
        child.instance_variable_set(:@orders, {})
      end

      def base_query(query)
        @base_query = query
      end

      def field(name, options = {}, &block)
        @fields[name.to_sym] = block || ->(query) { query.select(name) }
      end

      def filter(name, operator: nil, field: nil, &block)
        return unless block || operator

        @filters[name.to_sym] = block || ->(query, val) { send(operator, query, field || name, val) }
      end

      def order(name, &block)
        @orders[name.to_sym] = block || ->(query, dir) { query.order(name => dir) }
      end

      def inspect
        {
          fields: @fields,
          filters: @filters,
          orders: @orders
        }
      end
    end

    def initialize(base: {}, fields: [], filter: {}, order: {}, page: {})
      base(base)
      @query_fields = fields.map(&:to_sym)
      @query_filters = filter.symbolize_keys
      @query_order = order.symbolize_keys
      @query_pagination = page.symbolize_keys
    end

    # TODO: llamar scope ?
    def base(query = {})
      @query_base = query

      self
    end

    def query
      query = self.class.instance_variable_get(:@base_query).where(@query_base)
      query = apply_fields(query)
      query = apply_filters(query)
      query = apply_order(query)
      apply_pagination(query)
    end

    def run
      as_json(query)
    end

    delegate :first, to: :run

    # TODO: falla p = ProductQuery.new(base: {id: [1,2]}, fields: [:name])
    def meta
      query = self.class.instance_variable_get(:@base_query).where(@query_base)
      query = apply_filters(query)
      query = apply_order(query)

      {total_count: query.unscope(:select).count}
    end

    def find(id)
      @query_base[:id] = id
      @query_filters = {}
      @query_order = {}
      @query_pagination = {size: 1, number: 1}

      first
    end

    private

    def as_json(query)
      query.as_json
    end

    def apply_fields(query)
      query = query.select(:id)

      return query if @query_fields.blank?

      @query_fields.each do |field|
        block = self.class.instance_variable_get(:@fields)[field.to_sym]
        query = instance_exec(query, &block) if block
      end

      query
    end

    def apply_filters(query)
      return query if @query_filters.blank?

      @query_filters.each do |filter, value|
        block = self.class.instance_variable_get(:@filters)[filter]
        query = instance_exec(query, value, &block) if block
      end

      query
    end

    def apply_order(query)
      return query if @query_order.blank?

      orders = %i[asc desc]

      @query_order.each do |order, dir|
        next unless orders.include?(dir.downcase.to_sym)

        block = self.class.instance_variable_get(:@orders)[order]
        query = instance_exec(query, dir, &block) if block
      end

      query
    end

    def apply_pagination(query)
      return query if @query_pagination.blank?

      size = @query_pagination[:size].to_i
      number = @query_pagination[:number].to_i

      limit = size.positive? ? size : 20
      offset = ((number.positive? ? number : 1) - 1) * limit

      query.offset(offset).limit(limit)
    end

    ## FILTERS OPERATIONS

    def equal(query, field, val)
      query.where(field => val)
    end

    def contain(query, path, val)
      query.where("#{path} LIKE '%#{val}%'")
    end

    def gt(query, path, val)
      query.where("#{path} > ?", val)
    end

    def lt(query, path, val)
      query.where("#{path} < ?", val)
    end

    def range(query, path, val)
      query.where(path => val.is_a?(Range) ? val : val[0]..val[1])
    end
  end
end
