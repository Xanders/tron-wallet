module Wallet
  class DB
    getter conn
    @wallet : Wallet::Main
    @conn : ::DB::Database

    def initialize(@wallet)
      db_path = File.expand_path "#{ENV["HOME"]}/.local/tron-wallet"
      FileUtils.mkdir_p(db_path)
      @conn = ::DB.open "sqlite3://#{db_path}/wallet.db"
    end

    def setup
      tables = [] of String
      @conn.query "SELECT name FROM sqlite_master WHERE type='table'" do |res|
        res.each do
          tables << res.read(String)
        end
      end

      unless tables.includes? "accounts"
        @conn.exec "create table accounts (name text, value text)"
        @wallet.prompt.warn("Accounts table created")
      end

      unless tables.includes? "contracts"
        @conn.exec "create table contracts (name text, value text)"
        @wallet.prompt.warn("Contracts table created")
      end

      unless tables.includes? "settings"
        @conn.exec "create table settings (name text, value text)"
        @wallet.prompt.warn("Settings table created")
      end

      unless tables.includes? "addressbook"
        @conn.exec "create table addressbook (name text, value text)"
        @wallet.prompt.warn("Addressbook table created")
      end

      settings = get_settings

      unless settings.keys.size == 3
        @conn.exec("DELETE FROM settings")
        @wallet.prompt.warn("Wallet settings not found!")
        @wallet.controller.initial_setup
      end
    end

    def get_settings
      settings = {} of String => String

      @conn.query "SELECT name, value FROM settings" do |res|
        res.each do
          settings[res.read(String)] = res.read(String)
        end
      end

      return settings
    end

    def update_settings(node_url, max_commission, password)
      @conn.exec("INSERT INTO settings VALUES (?, ?)", args: ["node_url", node_url])
      @conn.exec("INSERT INTO settings VALUES (?, ?)", args: ["max_commission", max_commission])
      @conn.exec("INSERT INTO settings VALUES (?, ?)", args: ["transaction_password", password.to_s])

      return get_settings
    end

    #---------------------------------------------

    def get_accounts
      accounts = [] of String
      @conn.query "SELECT name FROM accounts" do |res|
        res.each do
          accounts << res.read(String)
        end
      end

      return accounts
    end

    def get_account(name)
      account = {} of String => String
      @conn.query "SELECT name, value FROM accounts WHERE name = ? LIMIT 1", args: [name] do |res|
        res.each do
          name = res.read
          next if name.nil?
          value = res.read(String)
          account[name.as(String)] = value
        end
      end
      return account
    end

    def create_account(name, data)
      @conn.exec("INSERT INTO accounts VALUES (?, ?)", args: [name, data])
    end

    def delete_account(name)
      @conn.exec("DELETE FROM accounts WHERE name = ?", args: [name])
    end

    def get_contracts
      contracts = {} of String => String
      @conn.query "SELECT name, value FROM contracts" do |res|
        res.each do
          contracts[res.read(String)] = res.read(String)
        end
      end

      return contracts
    end

    def add_contract(name, address)
      @conn.exec("INSERT INTO contracts VALUES (?, ?)", args: [name, address])
    end

    def delete_contract(name, address)
      @conn.exec("DELETE FROM contracts WHERE name = ? AND value = ?", args: [name, address])
    end

    def get_book
      book = {} of String => String
      @conn.query "SELECT name, value FROM addressbook" do |res|
        res.each do
          book[res.read(String)] = res.read(String)
        end
      end

      return book
    end

    def add_book(name, address)
      @conn.exec("INSERT INTO addressbook VALUES (?, ?)", args: [name, address])
    end

    def delete_book(name, address)
      @conn.exec("DELETE FROM addressbook WHERE name = ? AND value = ?", args: [name, address])
    end

    def encrypt(data, password)
      length = password.size
      phrase = password * ((32/length).to_i + 1)
      crypter = Crypt::Crypter.new(phrase)
      encrypted = crypter.encrypt(data)
      encoded = Base64.encode(encrypted)
      return encoded
    end

    def decrypt(data, password)
      length = password.size
      phrase = password * ((32/length).to_i + 1)
      crypter = Crypt::Crypter.new(phrase)
      decrypted_bytes = crypter.decrypt(Base64.decode(data))
      decoded = String.new(decrypted_bytes)
      data = Hash(String, String).from_json(decoded)
      return data
    end
  end
end