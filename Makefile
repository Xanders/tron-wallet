# Show this help
help:
	@cat $(MAKEFILE_LIST) | docker run --rm -i xanders/make-help

# Run the app
run:
	crystal src/tron-wallet.cr --error-trace --warnings none

# Run specs
test:
	crystal spec

# Build the binary
release:
	crystal build src/tron-wallet.cr -o build/tron-wallet --warnings none

# Clean build directory
clean:
	rm ./build/*

# Install binary locally
install:
	cp build/tron-wallet /usr/local/bin

# Install dependencies
shards:
	shards install

##
## With Docker
##

# Run the app from the Docker image
up:
	docker compose run --rm app

# Compile and run the app on the fly
debug:
	docker compose run --rm debug

# Install dependencies using Docker
docker-shards:
	docker compose run --rm debug shards install

# Start REPL session
repl:
	docker compose run --rm repl

# Build and push Docker image
deploy: image push

# Build the Docker image
image:
	docker compose build app

# Push the Docker image to registry
push:
	docker compose push app

# Pull the Docker image from registry
pull:
	docker compose pull app