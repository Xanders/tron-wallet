macro generate_case(namespace, list)
  case command
  {% for value in list.resolve %}
  when {{value}} then {{namespace.id}}_{{value.id}}(args)
  {% end %}
  {% if list.resolve.includes? "list" %}
  when "ls" then {{namespace.id}}_list(args)
  {% end %}
  {% if list.resolve.includes? "login" %}
  when "cd" then {{namespace.id}}_login(args)
  {% end %}
  {% if list.resolve.includes? "balance" %}
  when "ps" then {{namespace.id}}_balance(args)
  {% end %}
  else @wallet.prompt.error("Command not found")
  end
end

macro initialize_commands(list)
  def process(command : String)
    command, *args = command.split(" ")
    
    case command
    {% for value in list.resolve %}
    when {{value}} then {{value.id}}(args)
    {% end %}
    else
      generate_case("wallet", WALLET_COMMANDS)
    end
  ensure
    @wallet.prompt.say("\n")
  end
end

require "./controller/*"

module Wallet
  class Controller
    include WalletController
    include ContractsController
    include BookController
    include SettingsController
    include ServiceController
    include WitnessController

    @wallet : Wallet::Main
    @insecure_password : String?

    def initialize(@wallet)
      @insecure_password = ENV["TRON_WALLET_ONE_INSECURE_PASSWORD"]?
    end

    def ask_for_settings
      settings_edit(reconnect: false)
    end

    initialize_commands(SERVICE_COMMANDS)

    def connected?
      unless @wallet.connected
        @wallet.prompt.error("Wallet not connected, use `connect` command")
        return false
      end
      true
    end

    def authorized?
      unless @wallet.account
        @wallet.prompt.error("Not logged yet, use `login` command")
        return false
      end
      true
    end

    def one_password_for_all_mode?
      !!@insecure_password
    end

    def ask_for_password(custom_prompt = nil)
      @insecure_password || @wallet.prompt.mask(
        custom_prompt || "Enter password:", required: true
      ).not_nil!
    end
  end
end