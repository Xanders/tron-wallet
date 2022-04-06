module Wallet
  module SettingsController
    def settings(args)
      command = if args.any?
        args.shift
      else
        @wallet.prompt.select("Select command", %w(show edit)).not_nil!
      end

      generate_case("settings", %w(show edit))
    end

    def settings_show(args)
      settings = @wallet.db.get_settings

      @wallet.prompt.say("Node url: #{settings["node_url"]}")
      @wallet.prompt.say("Maximum commission in TRX: #{settings["max_commission"]}")
      @wallet.prompt.say("Request password for transactions? #{settings["transaction_password"]}")
    end

    def settings_edit(args = [] of String, reconnect = true)
      settings = @wallet.db.get_settings
      node_url = @wallet.prompt.ask("Enter node url:", default: settings["node_url"]? || "http://127.0.0.1:8090", required: true)
      max_commission = @wallet.prompt.ask("Maximum allowed trx commission for transaction?", default: settings["max_commission"]? || "100", match: /\A\d{2,4}\Z/, required: true)
      password = @wallet.prompt.yes?("Request password for transactions?")
      @wallet.db.update_settings(node_url, max_commission, password)
      @wallet.settings = @wallet.db.get_settings
      @wallet.prompt.ok("Settings updated!")
      if reconnect
        @wallet.node.reconnect
        @wallet.node.status
      end
    end
  end
end