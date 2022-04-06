require "term-prompt"
require "file_utils"
require "db"
require "sqlite3"
require "json"
require "http/client"
require "crypt"
require "crypt/crypter"
require "crypt/random"
require "base64"
require "./tron-wallet/db"
require "./tron-wallet/controller"
require "./tron-wallet/node"
require "./tron-wallet/converter"
require "./tron-wallet/utils"

module Wallet
  class Main
    getter prompt : Term::Prompt
    property settings
    property account, address
    property connected = false
    @controller : Wallet::Controller?
    @db : Wallet::DB?
    @node : Wallet::Node?
    @account : String?
    @address : String?

    def initialize
      @prompt = Term::Prompt.new()
      @settings = {} of String => String
      @account = nil
      @address = nil
      title
    end

    def node; @node.not_nil!; end
    def controller; @controller.not_nil!; end
    def db; @db.not_nil!; end

    def setup
      @controller = Wallet::Controller.new(self).not_nil!
      @db = Wallet::DB.new(self).not_nil!
      db.setup
      @settings = db.get_settings
      @node = Wallet::Node.new(self).not_nil!
      node.status
    end

    def title
      prompt.say("Tron wallet 0.1.0")
      prompt.say("Print `help` to see all commands")
      prompt.say("\n")
    end

    def run
      prompt.say("Log in to your account and feel great!")
      loop do
        result = prompt.ask("#{account}> ")
        break if result == "exit"
        next unless result
        controller.process(result.not_nil!)
      rescue Term::Reader::InputInterrupt
        prompt.say("^C\n")
      end
    end
  end
end

wallet = Wallet::Main.new
wallet.setup
wallet.run