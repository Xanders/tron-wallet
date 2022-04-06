run: 
	crystal src/tron-wallet.cr --error-trace --warnings none

release:
	crystal build src/tron-wallet.cr -o build/tron-wallet --warnings none

clean:
	rm ./build/*
