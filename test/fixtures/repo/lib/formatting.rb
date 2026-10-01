module Formatting
  def self.money(cents)
    "$%.2f" % (cents / 100.0)
  end
end
