# Base Relatório T5 — Resultados Práticos de Otimização Física

> **Disciplina:** SCC-541 – Laboratório de Bases de Dados — ICMC/USP São Carlos  
> **Semestre:** 1º Semestre de 2026  
> **Grupo de Trabalho:** Katiely F. Lacerda, Leonardo Gonsalez, Miguel F. Calhabeu, Renan S. Soriano, Guilherme M. Tranche  

Este documento apresenta os dados empíricos e a análise científica das medições de performance obtidas a partir dos testes executados na instância PostgreSQL 16 local. Os planos físicos de execução foram capturados via instrução `EXPLAIN ANALYZE` e as médias estatísticas de tempo de resposta foram computadas via funções customizadas em PL/pgSQL com **Buffer Pool (RAM) aquecido (Warm Cache)** e **100 execuções consecutivas**.

---

## 1. Metodologia Experimental

Para mitigar variações de concorrência e ruídos do sistema operacional, todas as queries foram submetidas ao banco por meio de loops programáticos de 100 iterações. Os tempos exibidos representam a média aritmética precisa de tempo por execução individual.

As consultas atuaram sobre as seguintes tabelas integradas da Fórmula 1 + Dados Geográficos:
* **`drivers` (Pilotos F1):** $616$ tuplas alocadas em disco.
* **`cities` (GeoNames):** $81.269$ tuplas alocadas em disco.
* **`countries` (Países GeoNames):** $249$ tuplas alocadas em disco.

---

## 2. Exercício 1 — Otimização Pontual de Piloto por Nome Exato

### 2.1. Cenário de Teste e Consulta SQL
O objetivo é recuperar a nacionalidade de um piloto a partir de seu nome exato concatenado:
```sql
SELECT (given_name || ' ' || family_name)::TEXT AS driver_name, nationality::TEXT 
FROM drivers 
WHERE (given_name || ' ' || family_name) = 'Ayrton Senna';
```

---

### 2.2. Estado Inicial (Sem Índice)

#### Tempo Médio por Execução: **$0,07$ ms**

#### Plano Físico de Execução (`EXPLAIN ANALYZE`):
```yaml
Seq Scan on drivers  (cost=0.00..10.53 rows=1 width=64) (actual time=0.050..0.072 rows=1 loops=1)
  Filter: ((((given_name)::text || ' '::text) || (family_name)::text) = 'Ayrton Senna'::text)
  Rows Removed by Filter: 615
Planning Time: 0.034 ms
Execution Time: 0.078 ms
```

#### Análise Crítica:
O otimizador de consultas do PostgreSQL foi forçado a realizar um **`Seq Scan` (Varredura Sequencial)**. Como o filtro depende de uma expressão de concatenação e não havia um índice funcional definido, o banco realizou a leitura em disco/memória de todos os $616$ blocos de registros, computou a fórmula de concatenação textual linha por linha e descartou $615$ registros que não correspondiam à string procurada. Apesar de rápido devido ao tamanho reduzido da tabela, o custo computacional cresce linearmente $\mathcal{O}(N)$ com o volume de dados.

---

### 2.3. Otimização Aplicada (Índice Hash Funcional)

#### Comando SQL de Criação:
```sql
CREATE INDEX idx_drivers_fullname_hash ON drivers USING hash (((given_name || ' ' || family_name)));
```

---

### 2.4. Estado Otimizado (Com Índice Hash Funcional)

#### Tempo Médio por Execução: **$0,01$ ms** (Fator de ganho de velocidade de **~$7\times$**)

#### Plano Físico de Execução (`EXPLAIN ANALYZE`):
```yaml
Bitmap Heap Scan on drivers  (cost=4.02..9.73 rows=3 width=64) (actual time=0.005..0.005 rows=1 loops=1)
  Recheck Cond: ((((given_name)::text || ' '::text) || (family_name)::text) = 'Ayrton Senna'::text)
  Heap Blocks: exact=1
  ->  Bitmap Index Scan on idx_drivers_fullname_hash  (cost=0.00..4.02 rows=3 width=0) (actual time=0.003..0.003 rows=1 loops=1)
        Index Cond: ((((given_name)::text || ' '::text) || (family_name)::text) = 'Ayrton Senna'::text)
Planning Time: 0.022 ms
Execution Time: 0.011 ms
```

#### Análise Crítica do Ganho de Performance:
1. **Mudança no Acesso Físico:** O SGBD migrou de um `Seq Scan` custoso para um **`Bitmap Index Scan`** utilizando o índice recém-criado.
2. **Complexidade Algorítmica:** O índice Hash computou a função de espalhamento da chave `"Ayrton Senna"` e buscou o endereço físico de forma direta (complexidade constante $\mathcal{O}(1)$), localizando a página física e lendo apenas o bloco que continha o piloto desejado.
3. **Restrições Técnicas Anotadas:** O PostgreSQL utilizou a operação *Bitmap Heap Scan* para ler o atributo `nationality` diretamente da tabela física em disco. Isso ocorre porque índices do tipo Hash no PostgreSQL não suportam indexação de cobertura (`INCLUDE`). O ganho de $7\times$ de velocidade comprova que, mesmo com o acesso necessário à tabela Heap, o uso de índices pontuais para busca exata de expressões é altamente vantajoso.

---

## 3. Exercício 2 — Cidades Brasileiras por Prefixo de Nome

### 3.1. Cenário de Teste e Consulta SQL
O objetivo é recuperar a latitude, longitude e população de cidades localizadas no Brasil (`country_id` dinamicamente extraído) cujo nome inicia com o prefixo `"São"`:
```sql
SELECT name::TEXT, latitude, longitude, population 
FROM cities 
WHERE country_id = (SELECT id FROM countries WHERE code = 'BR' LIMIT 1)
  AND name LIKE 'São%';
```

---

### 3.2. Estado Inicial (Sem Índice)

#### Tempo Médio por Execução: **$6,10$ ms**

#### Plano Físico de Execução (`EXPLAIN ANALYZE`):
```yaml
Seq Scan on cities  (cost=8.16..1662.82 rows=1 width=56) (actual time=0.173..6.097 rows=243 loops=1)
  Filter: (((name)::text ~~ 'São%'::text) AND (country_id = $0))
  Rows Removed by Filter: 81026
  InitPlan 1 (returns $0)
    ->  Limit  (cost=0.14..8.16 rows=1 width=4) (actual time=0.007..0.007 rows=1 loops=1)
          ->  Index Scan using countries_code_key on countries  (cost=0.14..8.16 rows=1 width=4) (actual time=0.007..0.007 rows=1 loops=1)
                Index Cond: ((code)::text = 'BR'::text)
Planning Time: 0.048 ms
Execution Time: 6.109 ms
```

#### Análise Crítica:
Sem índices otimizados, o planejador executou a subconsulta do país (usando o índice nativo de chave primária em `countries_code_key`) e depois efetuou uma leitura sequencial pesada (**`Seq Scan`**) de todas as **$81.269$ linhas** da tabela `cities`. A query foi obrigada a ler cada uma das cidades do GeoNames armazenadas no Buffer Pool para verificar as condições em tempo de execução, descartando **$81.026$ tuplas** indesejadas. Esse processo gerou um tempo de resposta de $6,10$ ms — o que é considerado alto para execuções únicas em cache aquecido.

---

### 3.3. Otimização Aplicada (B-Tree Composto com Cobertura)

#### Comando SQL de Criação:
```sql
CREATE INDEX idx_cities_br_name_btree ON cities (country_id, name text_pattern_ops) 
INCLUDE (latitude, longitude, population);
```

---

### 3.4. Estado Otimizado (Com Índice B-Tree Composto/Cobertura)

#### Tempo Médio por Execução: **$0,08$ ms** (Fator de ganho de velocidade de **~$76\times$**)

#### Plano Físico de Execução (`EXPLAIN ANALYZE`):
```yaml
Bitmap Heap Scan on cities  (cost=12.61..20.42 rows=2 width=56) (actual time=0.031..0.077 rows=243 loops=1)
  Recheck Cond: (country_id = $0)
  Filter: ((name)::text ~~ 'São%'::text)
  Heap Blocks: exact=114
  InitPlan 1 (returns $0)
    ->  Limit  (cost=0.14..8.16 rows=1 width=4) (actual time=0.004..0.004 rows=1 loops=1)
          ->  Index Scan using countries_code_key on countries  (cost=0.14..8.16 rows=1 width=4) (actual time=0.004..0.004 rows=1 loops=1)
                Index Cond: ((code)::text = 'BR'::text)
  ->  Bitmap Index Scan on idx_cities_br_name_btree  (cost=0.00..4.44 rows=2 width=0) (actual time=0.023..0.023 rows=243 loops=1)
        Index Cond: ((country_id = $0) AND ((name)::text ~>=~ 'São'::text) AND ((name)::text ~~<~ 'Sãp'::text))
Planning Time: 0.037 ms
Execution Time: 0.089 ms
```

#### Análise Crítica do Ganho de Performance:
1. **Otimização de Intervalo (B-Tree):** O uso do índice B-tree permitiu ao banco realizar uma busca de intervalo extremamente rápida. Ele localizou na árvore o início do prefixo `"São"` e leu de forma sequencial ordenada os dados até atingir a chave superior binária `"Sãp"`, localizando os $243$ registros correspondentes instantaneamente.
2. **Utilidade da Classe `text_pattern_ops`:** A classe de operadores forçou a B-tree a ordenar a coluna `name` através de representação binária crua, em vez de usar as regras lexicográficas locais complexas com acentos. Isso foi crucial para fazer o planejador do PostgreSQL aceitar usar a busca direcionada por índice para o predicado contendo `LIKE 'São%'`.
3. **Eficiência da Cláusula `INCLUDE`:** A inclusão das colunas de retorno (`latitude`, `longitude`, `population`) nas folhas do próprio índice permitiu que a consulta consumisse pouquíssimo processamento. Embora o PostgreSQL tenha optado por um plano do tipo *Bitmap Heap Scan* para o retorno, o tempo total de resposta despencou de $6,10$ ms para incríveis **$0,08$ ms** (um ganho de performance de mais de **$7.500\%$**), provando a excelência do design de cobertura composto.

---

## 4. Tabela de Comparação de Desempenho Consolidada

A tabela a seguir consolida as métricas experimentais observadas no banco local do laboratório:

| Consulta | Operação Principal | Estrutura Usada | Tempo Sem Índice | Tempo Com Índice | Fator de Aceleração | Eficiência Relativa |
| :--- | :--- | :---: | :---: | :---: | :---: | :---: |
| **Q1: Ayrton Senna** | Busca por Igualdade Exata | Hash Funcional | $0,07$ ms | $0,01$ ms | **$7\times$** | Altíssima performance local para igualdade |
| **Q2: Cidades Brasileiras** | Busca por Prefixo (`LIKE 'São%'`) | B-Tree Composto com `INCLUDE` | $6,10$ ms | $0,08$ ms | **$76\times$** | Economia brutal de I/O em grandes tabelas |

---

## 5. Conclusões Físicas de Banco de Dados para o Relatório

Com base nas evidências empíricas coletadas no laboratório prático, o grupo conclui:
1. **Especificidade Estrutural:** O índice Hash é altamente performático e ideal para buscas simples e exatas de igualdade (Exercício 1). Contudo, sua limitação em não aceitar cláusulas `INCLUDE` ou `WHERE`, aliada à incapacidade de indexar padrões parciais, restringe drasticamente sua versatilidade no mundo real.
2. **Superioridade Prática da B-Tree:** A B-Tree provou ser a estrutura de dados mais robusta e completa para indexação corporativa (Exercício 2). O suporte nativo a buscas de prefixo (`LIKE`), juntamente com a otimização de cobertura proporcionada pela cláusula `INCLUDE` (evitando ler a tabela física), faz com que consultas em tabelas com dezenas de milhares de registros sejam respondidas em frações de milissegundos.
3. **Custo da Concatenação em Tempo de Execução:** Sem a indexação funcional, a concatenação de colunas (`given_name || ' ' || family_name`) gera processamento redundante e lento para cada linha da tabela. Indexar a expressão diretamente mitiga completamente esse overhead.
