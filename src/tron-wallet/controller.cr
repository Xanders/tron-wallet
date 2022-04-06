macro generate_case(namespace, list)
  case command
  {% for value in list %}
  when {{value}} then {{namespace.id}}_{{value.id}}(args)
  {% end %}
  else @wallet.prompt.error("Command not found")
  end
end

macro initialize_commands(list)
  def process(command : String)
    command, *args = command.split(" ")
    if !@wallet.connected && command != "settings" 
      return @wallet.prompt.error("Wallet not connected")
    end
    
    case command
    {% for value in list %}
    when {{value}} then {{value.id}}(args)
    {% end %}
    else
      generate_case("wallet", %w(login logout list create import delete address backup balance send))
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

    @wallet : Wallet::Main
    initialize_commands(%w(wallet contracts book settings help block))
    def initialize(@wallet); end

    def initial_setup
      settings_edit(reconnect: false)
    end

    def authorized?
      unless @wallet.account
        @wallet.prompt.error("Not logged yet")
        return false
      end
      true
    end
  end
end