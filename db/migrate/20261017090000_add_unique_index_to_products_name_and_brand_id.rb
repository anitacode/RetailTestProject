class AddUniqueIndexToProductsNameAndBrandId < ActiveRecord::Migration[7.1]
  def change
    add_index :products, [:name, :brand_id], unique: true
  end
end
