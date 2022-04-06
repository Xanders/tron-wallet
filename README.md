# Tron wallet

### Build
* Install crystal-lang >= 1.3.0
* install libreadline-dev, libsqlite3-dev

```
crystal build src/tron-wallet.cr -o /usr/local/bin/tron-wallet --warnings none
```

### Usage
* print help for list available commands

### TODO
* refactor source, add with_decrypt block
* show energy and bandwith in balance
* add stacking TRX
* add inline swap coins through exchange
* add autocomplete commands by TAB
* edit contracts, book records and wallet names
* add link to transactions on tronscan