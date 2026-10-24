FROM golang:1.26 AS builder
WORKDIR /app
COPY go.mod ./
COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build -o webhook-adapter .

FROM alpine:latest
# GitHub API is HTTPS — need CA certs in the minimal image.
RUN apk add --no-cache ca-certificates
WORKDIR /app
COPY --from=builder /app/webhook-adapter .
EXPOSE 8080
CMD ["./webhook-adapter"]
