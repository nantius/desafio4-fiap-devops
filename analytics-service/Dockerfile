# Usa uma imagem oficial do Python
FROM python:3.11-slim

# Define o diretório de trabalho dentro do container
WORKDIR /app

# Copia os arquivos de dependências primeiro (para aproveitar cache)
COPY requirements.txt .

# Instala as dependências
RUN pip install --no-cache-dir -r requirements.txt

# Copia o restante do código da aplicação
COPY . .

# Expõe a porta (se sua aplicação for um servidor web)
EXPOSE 8005

# Run under the OpenTelemetry auto-instrumentation agent. botocore patching
# continues the distributed trace from the SQS message attributes that
# evaluation-service injected, and traces the DynamoDB writes.
CMD ["opentelemetry-instrument", "python", "app.py"]
