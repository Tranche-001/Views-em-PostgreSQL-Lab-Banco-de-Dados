# Docker – Banco de Dados SCC-541

Sobe um PostgreSQL 16 com o schema e os dados da disciplina já carregados automaticamente.

---

## Estrutura esperada de arquivos

Antes de subir o container, a pasta precisa ter esta estrutura:

```
docker-labbd/
├── Dockerfile
├── docker-compose.yml
├── schema.sql
├── carga_docker.sql
└── dados/
    ├── airports.csv
    ├── circuits.csv
    ├── cities.tsv
    ├── constructors.csv
    ├── constructor_standings.csv
    ├── countries.csv
    ├── drivers.csv
    ├── driver_standings.csv
    ├── featureCodes_en.tsv
    ├── iso-languagecodes.tsv
    ├── qualifying.csv
    ├── races.csv
    ├── regions.csv
    ├── results.csv
    └── timeZones.tsv
```

> **Coloque todos os CSVs e TSVs da disciplina dentro da pasta `dados/`.**

---

## Como usar

### 1. Subir pela primeira vez

```bash
docker compose up --build
```

O Postgres vai:
1. Criar o banco `labbd`
2. Executar `schema.sql` (cria todas as tabelas)
3. Executar `carga_docker.sql` (carrega todos os dados)

A carga leva **alguns minutos** na primeira execução (são ~85 000 aeroportos e ~81 000 cidades). Aguarde a mensagem:

```
labbd_postgres  | database system is ready to accept connections
```

### 2. Conectar

**Via psql (terminal):**
```bash
docker exec -it labbd_postgres psql -U labbd -d labbd
```

**Via pgAdmin / DBeaver:**
```
Host:     localhost
Porta:    5432
Banco:    labbd
Usuário:  labbd
Senha:    labbd123
```

### 3. Parar sem apagar os dados

```bash
docker compose down
```

### 4. Apagar tudo e recarregar do zero

```bash
docker compose down -v
docker compose up --build
```

---

## Verificar se a carga funcionou

Conecte e rode:

```sql
SELECT COUNT(*) FROM airports;    -- ~84 958
SELECT COUNT(*) FROM cities;      -- ~81 269
SELECT COUNT(*) FROM countries;   -- ~249
SELECT COUNT(*) FROM circuits;    -- ~76
SELECT COUNT(*) FROM drivers;     -- ~616
SELECT COUNT(*) FROM races;       -- ~1 146
```

---

## Rodar o script do T4

Com o container rodando:

```bash
docker exec -i labbd_postgres psql -U labbd -d labbd < t4_views.sql
```

Ou copie o arquivo para dentro do container e rode:

```bash
docker cp t4_views.sql labbd_postgres:/tmp/
docker exec -it labbd_postgres psql -U labbd -d labbd -f /tmp/t4_views.sql
```

---

## Problemas comuns

| Problema | Solução |
|----------|---------|
| Porta 5432 ocupada | Troque para `"5433:5432"` no `docker-compose.yml` e conecte na porta 5433 |
| Carga falhou pela metade | `docker compose down -v && docker compose up --build` |
| Arquivo não encontrado | Confirme que todos os CSVs estão dentro de `dados/` |
| Permissão negada no Docker | Linux: adicione seu usuário ao grupo docker com `sudo usermod -aG docker $USER` |
