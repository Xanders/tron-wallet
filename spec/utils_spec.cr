require "spec"
require "../src/tron-wallet/utils"

describe Wallet::Utils do
  describe ".tron_params" do
    it "works" do
      Wallet::Utils.tron_params(
        TronAddress.to_hex("TQQg4EL8o1BSeKJY4MJ8TB8XK7xufxFBvK"),
        (100.0 * 1000000).to_i64.to_s(16) # for example, 100 USDT
      ).should eq "0000000000000000000000419e62be7f4f103c36507cb2a753418791b1cdc1820000000000000000000000000000000000000000000000000000000005f5e100"
    end
  end
end