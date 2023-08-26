module Wallet
  module SettingsController
    SETTINGS_COMMANDS = %w(show edit)

    def settings(args)
      command = if args.any?
        args.shift
      else
        @wallet.prompt.select("Select command:", SETTINGS_COMMANDS).not_nil!
      end

      generate_case("settings", SETTINGS_COMMANDS)
    end

    def settings_show(args)
      settings = @wallet.db.get_settings

      @wallet.prompt.say("Tron node URL: #{settings["node_url"]}")
      @wallet.prompt.say("Maximum fee in TRX: #{settings["max_commission"]}")
    end

    def settings_edit(args = [] of String, reconnect = true)
      settings = @wallet.db.get_settings
      node_url = @wallet.prompt.ask("Tron node URL:", default: settings["node_url"]? || ENV["TRON_WALLET_DEFAULT_NODE_URL"]? || "http://127.0.0.1:8090", required: true)
      max_commission = @wallet.prompt.ask("Maximum allowed TRX fee for transaction:", default: settings["max_commission"]? || ENV["TRON_WALLET_DEFAULT_MAX_FEE"]? || "100", match: /\A\d{1,4}\Z/, required: true)
      @wallet.db.update_settings(node_url, max_commission)
      @wallet.settings = @wallet.db.get_settings
      @wallet.prompt.ok("Settings updated!")
      if reconnect
        @wallet.node.reconnect
        @wallet.node.status
      end
    end
  end
end