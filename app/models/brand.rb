class Brand < ApplicationRecord
  has_many :contacts, dependent: :destroy
  has_many :products
end
