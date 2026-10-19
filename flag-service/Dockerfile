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
EXPOSE 8002

# Run under the OpenTelemetry auto-instrumentation agent. It patches Flask,
# requests and psycopg2 at import time and exports OTLP to the Collector
# (endpoint/service name come from OTEL_* env vars set in the k8s manifest).
CMD ["opentelemetry-instrument", "python", "app.py"]
