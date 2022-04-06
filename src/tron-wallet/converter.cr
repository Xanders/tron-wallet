require "big"
require "digest"

# From https://github.com/russ/base58/blob/master/src/base58.cr
# but with different alphabet
module Base58
  extend self

  class DecodingError < RuntimeError
  end

  ALPHABET = "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz"
  BASE     = ALPHABET.size

  def encode(int_val : Number) : String
    base58_val = ""
    while int_val >= BASE
      mod = int_val % BASE
      base58_val = ALPHABET[mod.to_big_i, 1] + base58_val
      int_val = (int_val - mod).divmod(BASE).first
    end
    ALPHABET[int_val.to_big_i, 1] + base58_val
  end

  def decode(base58_val : String) : Number
    int_val = BigInt.new
    base58_val.reverse.split(//).each_with_index do |char, index|
      char_index = ALPHABET.index(char)
      raise DecodingError.new("Value passed not a valid Base58 String. (#{base58_val})") if char_index.nil?
      int_val += (char_index.to_big_i) * (BASE.to_big_i ** (index.to_big_i))
    end
    int_val
  end
end

# From https://github.com/kushkamisha/tron-format-address/blob/master/lib/crypto.ts
module TronAddress
  extend self

  FIRST_BYTE = "41"

  class CheckSumError < RuntimeError
  end

  def hex_to_bytes(hex : String) : Bytes
    unless hex.size % 2 == 0
      raise ArgumentError.new "argument should have even length"
    end

    Bytes.new(hex.size // 2).map_with_index do |_, index|
      hex[(index * 2)..(index * 2 + 1)].to_u8(16)
    end
  end

  def check_sum_for(hex : String) : String
    bytes = hex_to_bytes(hex)
    sha1 = Digest::SHA256.new.update(bytes).final
    sha2 = Digest::SHA256.new.update(sha1).final
    sha2[...4].hexstring
  end

  # convert hex beginning with 0x to base58
  def plain_hex_to_base58(hex : String) : String
    hex = FIRST_BYTE + hex[2..]
    to_base58(hex)
  end

  # convert base58 to hex beginning with 0x
  def base58_to_plain_hex(base58 : String) : String
    hex = to_hex(base58)
    "0x#{hex[2..]}"
  end

  def to_base58(hex : String) : String
    hex += check_sum_for(hex)
    Base58.encode hex.to_big_i(16)
  end

  def to_hex(base58 : String) : String
    if base58.size <= 4
      raise ArgumentError.new "argument should have length more than 4"
    end

    address = Base58.decode(base58).to_s(16)

    hex, check_sum = address[...-8], address[-8..]

    raise CheckSumError.new unless check_sum == check_sum_for(hex)

    hex
  end
end