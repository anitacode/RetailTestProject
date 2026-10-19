class AlertPolicy
  class Scope
    def initialize(brand, scope)
      @brand = brand
      @scope = scope
    end

    def resolve
      return @scope.none unless @brand

      @scope.where(brand_id: @brand.id)
    end
  end
end
