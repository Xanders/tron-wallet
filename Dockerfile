FROM crystallang/crystal:1.4.0-alpine as builder

RUN apk add readline-dev readline-static \
            sqlite-dev sqlite-static \
            ncurses-dev ncurses-static

WORKDIR /project
COPY . .
RUN crystal spec \
 && echo "Building app..." \
 && crystal build --release --static src/tron-wallet.cr

ENV HOME=/home
ENTRYPOINT ["/project/tron-wallet"]

## Building from scratch does not work because of SSL certs

# FROM scratch
# ENV HOME=/home
# COPY --from=builder /project/tron-wallet /tron-wallet
# ENTRYPOINT ["/tron-wallet"]