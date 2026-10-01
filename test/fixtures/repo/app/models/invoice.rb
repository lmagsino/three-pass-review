class Invoice < ApplicationRecord
  belongs_to :customer
  has_many :line_items

  SORTABLE = %w[created_at total].freeze

  def self.sorted(params)
    order("#{params[:sort]} DESC")
  end

  def self.recent
    where("created_at > ?", 30.days.ago)
  end

  def total_due
    line_items.sum(&:amount) - customer.credit
  end

  def helper_01
    :helper_01
  end

  def helper_02
    :helper_02
  end

  def helper_03
    :helper_03
  end

  def helper_04
    :helper_04
  end

  def helper_05
    :helper_05
  end

  def helper_06
    :helper_06
  end

  def helper_07
    :helper_07
  end

  def helper_08
    :helper_08
  end

  def helper_09
    :helper_09
  end

  def helper_10
    :helper_10
  end

  def helper_11
    :helper_11
  end

  def helper_12
    :helper_12
  end

  def helper_13
    :helper_13
  end

  def helper_14
    :helper_14
  end

  def helper_15
    :helper_15
  end

  def helper_16
    :helper_16
  end

  def helper_17
    :helper_17
  end

  def helper_18
    :helper_18
  end

  def helper_19
    :helper_19
  end

  def helper_20
    :helper_20
  end

  def overdue?
    due_on <= Date.current
  end
end
