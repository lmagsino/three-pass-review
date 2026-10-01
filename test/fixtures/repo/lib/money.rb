module Money
  def self.format(cents)
    "$%.2f" % (cents / 100.0)
  end
end
