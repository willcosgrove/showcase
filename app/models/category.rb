class Category < ApplicationRecord
  has_many :open_dances, dependent: :nullify,
    class_name: 'Dance', foreign_key: :open_category_id
  has_many :closed_dances, dependent: :nullify,
    class_name: 'Dance', foreign_key: :closed_category_id
  has_many :solo_dances, dependent: :nullify,
    class_name: 'Dance', foreign_key: :solo_category_id
  has_many :routine_dances, dependent: :nullify,
    class_name: 'Solo', foreign_key: :category_override_id
  has_many :multi_dances, dependent: :nullify,
    class_name: 'Dance', foreign_key: :multi_category_id

  has_many :extensions, dependent: :destroy,
    class_name: 'CatExtension'

  validates :name, presence: true, uniqueness: true
  validates :order, presence: true, uniqueness: true

  validates :day, chronic: true, allow_blank: true
  validates :time, chronic: true, allow_blank: true

  def part
    nil
  end
end
