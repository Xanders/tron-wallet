require "spec"
require "../src/tron-wallet/converter"

describe TronAddress do
  # From https://github.com/tronprotocol/documentation/blob/master/TRX/Tron-overview.md#62-mainnet-addresses-begin-with-41
  hex_1 = "0x5a523b449890854c8fc460ab602df9f31fe4293f"
  base58_1 = "TJCnKsPa7y5okkXvQAidZBzqx3QyQ6sxMW"

  # From https://github.com/kushkamisha/tron-format-address/blob/master/test/crypto.test.ts
  hex_2 = "0x1a6ac17c82ad141ebc524a9ffc94965848f35279"
  base58_2 = "TCNtTa1rveKkovHR2ebABu4K66U6ocUCZX"
  hex_3 = "0x2eb90f8356345c903d9f85e58d1b8177890adfb6"
  base58_3 = "TEEFn7rQqx4Xc3GL1Bx27A155xAj7w5W7a"
  hex_4 = "0x49a5f0cda413ab723fff9baf956329ecfe5d1a23"
  base58_4 = "TGgd7pXdZALo9GyT4pmF2tT6JRf7ETWVcL"

  describe ".plain_hex_to_base58" do
    it "works" do
      TronAddress.plain_hex_to_base58(hex_1).should eq base58_1
      TronAddress.plain_hex_to_base58(hex_2).should eq base58_2
      TronAddress.plain_hex_to_base58(hex_3).should eq base58_3
      TronAddress.plain_hex_to_base58(hex_4).should eq base58_4
    end
  end

  describe ".base58_to_plain_hex" do
    it "works" do
      TronAddress.base58_to_plain_hex(base58_1).should eq hex_1
      TronAddress.base58_to_plain_hex(base58_2).should eq hex_2
      TronAddress.base58_to_plain_hex(base58_3).should eq hex_3
      TronAddress.base58_to_plain_hex(base58_4).should eq hex_4
    end
  end
end