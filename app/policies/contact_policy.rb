class ContactPolicy
  class Scope
    def initialize(brand, scope)
      @brand = brand
      @scope = scope
    end

    def resolve
      @brand ? @scope.where(brand_id: @brand.id) : @scope.none
    end
  end
end
