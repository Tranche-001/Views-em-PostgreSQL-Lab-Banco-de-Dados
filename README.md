# SCC-541 – Laboratório de Bases de Dados  
## Trabalho Prático T4 – Visões em PostgreSQL

> **Disciplina:** SCC-541 – Lab. de Bases de Dados — ICMC/USP São Carlos  
> **Semestre:** 1º Semestre de 2026  
> **Entrega:** 20 de maio de 2026  

---

### Equipe

| Nome | NUSP |
|------|------|
| Katiely Feitosa de Lacerda | 12777100 |
| Leonardo Gonsalez | 15657074 |
| Miguel Filippo Calhabeu | 15480331 |
| Renan Silva Soriano | 11794824 |
| Guilherme Motta Tranche | 13671549 |

---

## Conteúdo do Repositório

```
.
├── t4_views.sql               # Script SQL completo (todos os exercícios)
├── Relatorio_T4_Views.docx    # Relatório em Word
└── README.md                  # Este arquivo
```

---

## Descrição

O objetivo deste trabalho é praticar o uso de **visões** (*views*) no PostgreSQL utilizando a base de dados da **Fórmula 1 + Cidades + Aeroportos** construída ao longo da disciplina.

Foram implementadas as seguintes visões:

| Exercício | Nome da Visão | Tipo | Descrição |
|-----------|--------------|------|-----------|
| 1 | `Aeroportos_Brasileiros` | Materializada | Aeroportos vinculados a cidades brasileiras |
| 2 | `Aeroportos_sem_cidades` | Transiente | Aeroportos sem `city_id` associado |
| 2 | `Cidades_brasileiras` | Transiente | Cidades do Brasil com ≥ 100 000 hab. |
| 3 | `Circuitos_completa` | Transiente | Circuitos com localização geográfica completa |
| 4 | `Problemas_aeroportos` | Transiente | Aeroportos sem cidade a ≤ 10 km de cidades BR |
| 5 | `Correcao_aeroportos` | Transiente (atualizável) | Aeroportos candidatos à correção de `city_id` |

---

## Pré-requisitos

- **PostgreSQL 13+**
- Base de dados criada e carregada conforme as atividades anteriores da disciplina
- Extensões necessárias (instaladas automaticamente pelo script):
  ```sql
  CREATE EXTENSION IF NOT EXISTS cube;
  CREATE EXTENSION IF NOT EXISTS earthdistance;
  ```

---

## Como Executar

1. Certifique-se de que a base de dados da disciplina está carregada e acessível.
2. Conecte-se ao banco com `psql` ou pela sua ferramenta preferida (DBeaver, pgAdmin, etc.).
3. Execute o script SQL:

```bash
psql -U <usuario> -d <banco> -f t4_views.sql
```

> O script cria, testa e — no Exercício 5 — atualiza dados. Execute em ambiente de desenvolvimento/teste.

---

## Resumo dos Exercícios

### Exercício 1 — `Aeroportos_Brasileiros` (Visão Materializada)

- Junta `airports`, `cities` e `countries` filtrando pelo código `'BR'`.
- **Item (a):** criação da visão materializada e exibição de exemplos.
- **Item (b):** comparação de desempenho com `EXPLAIN ANALYZE` (≥ 5 execuções): a visão materializada é ~62× mais rápida que a consulta direta nas tabelas-base (~0,6 ms vs ~35,9 ms), ocupando 1 032 kB de armazenamento.
- **Item (c):** demonstração da necessidade de `REFRESH MATERIALIZED VIEW` após inserção nas tabelas-base.

### Exercício 2 — Aeroportos sem Cidade e Associação por Distância

- **`Aeroportos_sem_cidades`:** filtra `airports` onde `city_id IS NULL`.
- **`Cidades_brasileiras`:** cidades do Brasil com `population >= 100000`.
- Associação entre as duas visões usando `Earth_Distance` (extensão `EarthDistance`) com CTE (`WITH`) para isolar o cálculo de distância, retornando pares aeroporto–cidade com distância ≤ 10 km.

### Exercício 3 — `Circuitos_completa`

- Apresenta todos os circuitos com localização geográfica completa (cidade, país, continente).
- Utiliza **LEFT JOINs** para incluir circuitos sem `city_id` — garantindo que todos os 76 circuitos apareçam no resultado.

### Exercício 4 — `Problemas_aeroportos`

- Filtra os aeroportos de `Aeroportos_sem_cidades` que possuem ao menos uma cidade de `Cidades_brasileiras` a ≤ 10 km.
- Esses aeroportos representam **candidatos à correção**: existem fisicamente próximos a uma grande cidade brasileira, mas o vínculo não está registrado na base.

### Exercício 5 — `Correcao_aeroportos` e UPDATE via Visão

- Visão derivada diretamente de `airports` (sem junções) — portanto **atualizável automaticamente** pelo PostgreSQL (AUVis).
- Para cada aeroporto, seleciona a cidade brasileira mais próxima usando `DISTINCT ON` e executa `UPDATE` diretamente na visão, corrigindo `city_id`.
- Após a correção, os aeroportos deixam de aparecer em `Aeroportos_sem_cidades` e `Problemas_aeroportos`.

---

## Decisões de Projeto

| Decisão | Justificativa |
|---------|---------------|
| LEFT JOIN em `Circuitos_completa` | O enunciado exige que **todos** os circuitos apareçam, mesmo sem cidade vinculada |
| CTE (`WITH`) para distâncias | Evita repetição do cálculo `Earth_Distance` e melhora a legibilidade |
| `DISTINCT ON` no Exercício 5 | Seleciona apenas a cidade mais próxima por aeroporto de forma eficiente no PostgreSQL |
| Visão atualizável sem JOIN | A visão `Correcao_aeroportos` usa apenas `airports` para ser AUVis e permitir `UPDATE` direto |
| Extensões `cube` + `earthdistance` | Solução nativa do PostgreSQL para cálculo de distância geográfica (Haversine) |

---

## Referências

- [PostgreSQL Docs – CREATE MATERIALIZED VIEW](https://www.postgresql.org/docs/current/sql-creatematerializedview.html)
- [PostgreSQL Docs – earthdistance](https://www.postgresql.org/docs/current/earthdistance.html)
- [Kaggle – Formula 1 Championships (1950-2025)](https://www.kaggle.com/datasets/rohanrao/formula-1-world-championship-1950-2020)
- [GeoNames](https://www.geonames.org/)
- [OurAirports](https://ourairports.com/data/)
