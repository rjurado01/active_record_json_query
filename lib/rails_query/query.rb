module RailsQuery
  class Query
    @base = nil

    class << self
      attr_reader :base, :fields, :filters, :orders

      def inherited(child)
        super

        child.instance_variable_set(:@fields, {})
        child.instance_variable_set(:@filters, {})
        child.instance_variable_set(:@orders, {})
      end

      def init(query = nil)
        @base = query
      end

      def field(name, options = {}, &block)
        @fields[name.to_sym] = Field.new(name, options, block)
      end

      def filter(name, options = {}, &block)
        @filters[name.to_sym] = Filter.new(name, options, block)
      end

      def order(name, options = {}, &block)
        @orders[name.to_sym] = Order.new(name, options, block)
      end

      def inspect
        {
          fields: @fields,
          filters: @filters,
          orders: @orders
        }
      end
    end

    def initialize(scope: {}, fields: [], filters: {}, order: {}, page: {})
      @query_scope = scope
      @query_fields = fields.map(&:to_sym).uniq
      @query_filters = filters.symbolize_keys
      @query_order = order.symbolize_keys
      @query_pagination = page.symbolize_keys
    end

    def query
      query = self.class.base.where(@query_scope)
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
      query = self.class.base.where(@query_scope)
      query = apply_filters(query)
      query = apply_order(query)

      {total_count: query.unscope(:select).count}
    end

    def find(id)
      @query_scope[:id] = id
      @query_filters = {}
      @query_order = {}
      @query_pagination = {size: 1, number: 1}

      first
    end

    private

    def as_json(query)
      query.as_json(@query_as_json)
    end

    def apply_fields(query)
      query = query.select(:id)

      return query if @query_fields.blank?

      @query_as_json = {}

      @query_fields.each do |field|
        field = self.class.fields[field.to_sym]
        query = instance_exec(query, &field.block)

        @query_as_json.merge!(field.as_json) if field.as_json
      end

      query
    end

    def apply_filters(query)
      return query if @query_filters.blank?

      @query_filters.each do |filter_name, value|
        filter = self.class.filters[filter_name]
        query = filter.apply(query, value) if filter
      end

      query
    end

    def apply_order(query)
      return query if @query_order.blank?

      @query_order.each do |order_name, dir|
        order = self.class.orders[order_name]
        query = order.apply(query, dir) if order
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
  end
end
