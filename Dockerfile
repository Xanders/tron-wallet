FROM crystallang/crystal:1.8.1-alpine as base

RUN apk add readline-dev readline-static \
            sqlite-dev sqlite-static \
            ncurses-dev ncurses-static


FROM base as builder

WORKDIR /project

COPY . .

RUN crystal spec \
 && echo "Building app..." \
 && crystal build --release --static src/tron-wallet.cr


FROM scratch

ENV HOME=/home

COPY --from=builder /etc/ssl /etc/ssl
COPY --from=builder /project/tron-wallet /tron-wallet

ENTRYPOINT ["/tron-wallet"]