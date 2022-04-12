run: 
	crystal src/tron-wallet.cr --error-trace --warnings none

release:
	crystal build src/tron-wallet.cr -o build/tron-wallet --warnings none

clean:
	rm ./build/*

# Show this help
help:
	@cat $(MAKEFILE_LIST) | docker run --rm -i xanders/make-help

# Install dependencies
shards:
	shards install

##
## With Docker
##

# Run the app in Docker
tw:
	docker-compose run --rm app

# Build the Docker image
image:
	docker-compose build

# Push the Docker image to registry
push:
	docker-compose push

# Pull the Docker image from registry
pull:
	docker-compose pull