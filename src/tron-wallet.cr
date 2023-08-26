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
require "secp256k1"
require "./tron-wallet/db"
require "./tron-wallet/controller"
require "./tron-wallet/node"
require "./tron-wallet/converter"
require "./tron-wallet/utils"

module Wallet
  class Main
    getter prompt do Term::Prompt.new end

    # Cannot initialize them in initializer: https://github.com/crystal-lang/crystal/issues/12449
    getter controller do Controller.new(self) end
    getter db do DB.new(self) end
    getter node do Node.new(self) end

    property settings : Hash(String, String) do db.get_settings end
    property account : String?
    property address : String?
    property connected = false
    property debug = false

    def initialize
      intro
      db.setup
    end

    def intro
      prompt.ok("\nTron Wallet #{{{ `shards version #{__DIR__}`.stringify }}}")
      prompt.warn("WARNING: THE SOFTWARE IS PROVIDED “AS IS”, WITHOUT WARRANTY OF ANY KIND, under MIT license.")
      prompt.warn("That means you can lose all your real money and we will not care about. Sorry.\n")

      if controller.one_password_for_all_mode?
        prompt.error("You're using `TRON_WALLET_ONE_INSECURE_PASSWORD`, please be sure you're on testnet, never use it on mainnet!\n")
      end

      prompt.keypress("Press any key if you understand that")
    end

    def run
      prompt.say("\nConnecting to #{settings["node_url"]}")

      if node.status
        prompt.say("Node is synced. Log in to your account and feel great!")
      end

      controller.fill_contracts_from_env!

      prompt.say("Enter `help` to see all the commands")

      want_to_exit = false

      loop do
        result = prompt.ask("#{account}> ")
        break if result == "exit"
        next unless result
        want_to_exit = false
        controller.process(result.not_nil!)
      rescue Term::Reader::InputInterrupt
        if want_to_exit
          break
        else
          prompt.say("^C")
          prompt.say("Press again if you want to exit", color: :dark_grey)
          want_to_exit = true
        end
      end
    end

    def debug?
      @debug
    end

    def debug!(message)
      prompt.say("DEBUG: " + message, color: :dim_grey) if debug?
    end
  end
end

Wallet::Main.new.run