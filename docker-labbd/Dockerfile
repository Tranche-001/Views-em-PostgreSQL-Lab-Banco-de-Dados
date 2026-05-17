FROM postgres:16-alpine

# Variáveis do banco
ENV POSTGRES_DB=labbd
ENV POSTGRES_USER=labbd
ENV POSTGRES_PASSWORD=labbd123

# Copia os scripts SQL para o entrypoint do Postgres
# Tudo em /docker-entrypoint-initdb.d/ é executado na primeira inicialização
COPY schema.sql          /docker-entrypoint-initdb.d/01_schema.sql
COPY carga_docker.sql    /docker-entrypoint-initdb.d/02_carga.sql

# Copia os arquivos de dados para /dados/ dentro do container
# (o carga_docker.sql lê de /dados/)
COPY dados/              /dados/
