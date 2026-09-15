# Same shape as the interview project's service image: multi-stage Go build
# on alpine. Proves `docker build`, the Go module proxy, and a static binary.
FROM golang:1.26.8-alpine3.24 AS build
WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 go build -trimpath -o /out/smoke .

FROM alpine:3.21.7
COPY --from=build /out/smoke /usr/local/bin/smoke
ENTRYPOINT ["smoke"]
