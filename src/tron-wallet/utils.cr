module Wallet
  module Utils
    extend self

    def prepend_zeroes(size : Int32, value : String) : String
      return "0" * (size - value.size) + value
    end

    def tron_params(*values : String) : String
      values.map { |value| prepend_zeroes(64, value) }.join
    end
  end
end