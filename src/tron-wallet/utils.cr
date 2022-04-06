module Wallet
  module Utils
    extend self

    def prepend_zeroes(size : Int32, value : String) : String
      return "0" * (size - value.size) + value
    end

    def tron_params(*values : String) : String
      string = ""
      values.each {|value| string += prepend_zeroes(64, value)}
      return string
    end
  end
end