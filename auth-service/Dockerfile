FROM golang:1.25 AS builder

WORKDIR /app

COPY go.mod go.sum ./

COPY . .

# Ensure go.sum is consistent, then build a static binary
RUN go mod tidy
RUN CGO_ENABLED=0 GOOS=linux go build -o auth-service .

# Etapa 2: imagem final
FROM alpine:latest

WORKDIR /app

# Copia apenas o binário da etapa anterior
COPY --from=builder /app/auth-service .

# Porta exposta (se sua aplicação tiver servidor HTTP)
EXPOSE 8001

# Comando de inicialização
CMD ["./auth-service"]
