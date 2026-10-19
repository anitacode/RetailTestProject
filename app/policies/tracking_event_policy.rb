class TrackingEventPolicy
  class Scope
    def initialize(brand, scope)
      @brand = brand
      @scope = scope
    end

    def resolve
      return @scope.none unless @brand

      @scope.joins(:product).where(products: { brand_id: @brand.id })
    end
  end
end
