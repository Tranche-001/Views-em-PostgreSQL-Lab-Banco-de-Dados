-- ============================================================
-- SCC-541 Laboratório de Bases de Dados – 2026
-- Trabalho Prático T5 – Exercícios sobre Índices
-- Grupo: Katiely Feitosa de Lacerda   – 12777100
--        Leonardo Gonsalez            – 15657074
--        Miguel Filippo Calhabeu      – 15480331
--        Renan Silva Soriano          – 11794824
--        Guilherme Motta Tranche      – 13671549
-- ============================================================

-- ============================================================
-- FUNÇÕES DE MEDIÇÃO DE TEMPO (ADAPTADAS DO ENUNCIADO)
-- ============================================================

-- ------------------------------------------------------------
-- Função adaptada para o Exercício 1 (Retorna Nome e Nacionalidade)
-- Executa a query passada 100 vezes e imprime o tempo total médio
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION Mede_Tempo_Q1(Q TEXT)
RETURNS TABLE (driver_name TEXT, nationality TEXT) AS $$
DECLARE
    TIni TIMESTAMP; 
    TFim TIMESTAMP;
    i INT;
    Diff BIGINT;
BEGIN
    -- Registra o tempo inicial
    TIni := CLOCK_TIMESTAMP();
    
    FOR i IN 1..100 LOOP
        EXECUTE Q;
    END LOOP;
    
    -- Registra o tempo final
    TFim := CLOCK_TIMESTAMP();
    
    -- Calcula a diferença média por execução em microssegundos (ou milisegundos dependendo da escala)
    -- Multiplicamos por 1000 para milissegundos
    Diff := ROUND((EXTRACT(EPOCH FROM TFim) - EXTRACT(EPOCH FROM TIni)) * 1000 / 100);
    
    RAISE NOTICE 'Tempo médio por execução (100 execuções): % ms', Diff;
    
    -- Retorna o resultado da consulta recebida para validação
    RETURN QUERY EXECUTE Q;
END;
$$ LANGUAGE plpgsql;

-- ------------------------------------------------------------
-- Função adaptada para o Exercício 2 (Retorna Cidades: nome, lat, long, pop)
-- Executa a query passada 100 vezes e imprime o tempo total médio
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION Mede_Tempo_Q2(Q TEXT)
RETURNS TABLE (city_name TEXT, latitude DOUBLE PRECISION, longitude DOUBLE PRECISION, population BIGINT) AS $$
DECLARE
    TIni TIMESTAMP; 
    TFim TIMESTAMP;
    i INT;
    Diff BIGINT;
BEGIN
    -- Registra o tempo inicial
    TIni := CLOCK_TIMESTAMP();
    
    FOR i IN 1..100 LOOP
        EXECUTE Q;
    END LOOP;
    
    -- Registra o tempo final
    TFim := CLOCK_TIMESTAMP();
    
    -- Calcula a diferença média por execução em milissegundos
    Diff := ROUND((EXTRACT(EPOCH FROM TFim) - EXTRACT(EPOCH FROM TIni)) * 1000 / 100);
    
    RAISE NOTICE 'Tempo médio por execução (100 execuções): % ms', Diff;
    
    -- Retorna o resultado da consulta recebida para validação
    RETURN QUERY EXECUTE Q;
END;
$$ LANGUAGE plpgsql;


-- ============================================================
-- EXERCÍCIO 1 – Busca de Piloto por Nome Exato e Nacionalidade
-- ============================================================

-- ------------------------------------------------------------
-- (a) Consulta de Teste e Medição Sem Índice
-- ------------------------------------------------------------

-- Definição da query para buscar a nacionalidade de Ayrton Senna pelo nome exato:
-- SELECT given_name || ' ' || family_name AS driver_name, nationality FROM drivers WHERE given_name || ' ' || family_name = 'Ayrton Senna';

-- Teste de medição de tempo sem índice
SELECT * FROM Mede_Tempo_Q1($$
    SELECT (given_name || ' ' || family_name)::TEXT AS driver_name, nationality::TEXT 
    FROM drivers 
    WHERE (given_name || ' ' || family_name) = 'Ayrton Senna';
$$);

-- Análise do plano de execução sem índice
EXPLAIN ANALYZE
SELECT (given_name || ' ' || family_name)::TEXT AS driver_name, nationality::TEXT 
FROM drivers 
WHERE (given_name || ' ' || family_name) = 'Ayrton Senna';

-- ------------------------------------------------------------
-- (b) Criação do Índice Hash Funcional
-- ------------------------------------------------------------
-- JUSTIFICATIVA DA ESCOLHA:
-- 1. O Exercício 1 realiza uma busca por IGUALDADE EXATA ('=') sobre uma expressão concatenada.
-- 2. De acordo com as diretrizes do enunciado, devemos alternar o uso de B-tree e Hash entre as duas questões.
-- 3. O índice Hash é a estrutura ideal no PostgreSQL para igualdades exatas (complexidade O(1) média),
--    enquanto a Questão 2 obrigatoriamente exigirá B-tree devido à busca por padrão LIKE 'nome%'.
-- 4. O índice é "Funcional" pois indexa o resultado da expressão (given_name || ' ' || family_name).
-- 
-- ATENÇÃO SOBRE LIMITAÇÕES:
-- Índices Hash no PostgreSQL NÃO suportam a cláusula 'INCLUDE' ou 'WHERE'. O indexador acusa erro de sintaxe
-- se tentarmos indexar 'nationality' como INCLUDE em um índice USING hash.

DROP INDEX IF EXISTS idx_drivers_fullname_hash;

CREATE INDEX idx_drivers_fullname_hash ON drivers USING hash (((given_name || ' ' || family_name)));

-- ------------------------------------------------------------
-- (c) Medição de Tempo Com Índice Criado
-- ------------------------------------------------------------

-- Teste de medição de tempo com índice
SELECT * FROM Mede_Tempo_Q1($$
    SELECT (given_name || ' ' || family_name)::TEXT AS driver_name, nationality::TEXT 
    FROM drivers 
    WHERE (given_name || ' ' || family_name) = 'Ayrton Senna';
$$);

-- Análise do plano de execução com o índice criado (espera-se "Index Scan using idx_drivers_fullname_hash")
EXPLAIN ANALYZE
SELECT (given_name || ' ' || family_name)::TEXT AS driver_name, nationality::TEXT 
FROM drivers 
WHERE (given_name || ' ' || family_name) = 'Ayrton Senna';


-- ============================================================
-- EXERCÍCIO 2 – Busca de Cidades Brasileiras por Prefixo de Nome
-- ============================================================

-- ------------------------------------------------------------
-- (a) Consulta de Teste e Medição Sem Índice
-- ------------------------------------------------------------

-- A consulta recupera latitude, longitude e população de cidades do Brasil (código 'BR')
-- cujo nome começa com o padrão 'São' (por exemplo, São Paulo, São José, etc.)

-- Teste de medição de tempo sem índice
SELECT * FROM Mede_Tempo_Q2($$
    SELECT name::TEXT, latitude, longitude, population 
    FROM cities 
    WHERE country_id = (SELECT id FROM countries WHERE code = 'BR' LIMIT 1)
      AND name LIKE 'São%';
$$);

-- Análise do plano de execução sem índice
EXPLAIN ANALYZE
SELECT name::TEXT, latitude, longitude, population 
FROM cities 
WHERE country_id = (SELECT id FROM countries WHERE code = 'BR' LIMIT 1)
  AND name LIKE 'São%';

-- ------------------------------------------------------------
-- (b) Criação do Índice B-tree Otimizado (Composto com INCLUDE)
-- ------------------------------------------------------------
-- JUSTIFICATIVA DA ESCOLHA:
-- 1. A consulta utiliza um operador de busca por padrão e faixa ('LIKE'), o que inviabiliza o índice Hash.
--    O índice B-tree é estruturalmente obrigatório aqui por suportar buscas de intervalo e correspondência de prefixo.
-- 2. Para obter a máxima performance, criamos um índice B-Tree Composto nas colunas de busca '(country_id, name)'.
-- 3. Usamos a classe de operador 'text_pattern_ops' na coluna 'name' para garantir que o PostgreSQL use
--    o índice mesmo em bancos de dados que não usam a localidade padrão 'C' (garante compatibilidade do LIKE 'São%').
-- 4. Adicionamos a cláusula 'INCLUDE (latitude, longitude, population)'. Isso cria um índice de cobertura,
--    permitindo que a consulta seja respondida inteiramente através de um "Index Only Scan",
--    eliminando a necessidade de buscar os dados reais na tabela ('Heap Fetches'), o que economiza I/O de disco.
-- 5. Nota de Design: Não utilizamos um índice parcial 'WHERE country_id = (subquery)' porque o PostgreSQL
--    não aceita subconsultas dinâmicas ou mutáveis na cláusula WHERE do índice. O índice composto cobrindo
--    ambas as colunas é a solução mais flexível e robusta.

DROP INDEX IF EXISTS idx_cities_br_name_btree;

CREATE INDEX idx_cities_br_name_btree ON cities (country_id, name text_pattern_ops) 
INCLUDE (latitude, longitude, population);

-- ------------------------------------------------------------
-- (c) Medição de Tempo Com Índice Criado
-- ------------------------------------------------------------

-- Teste de medição de tempo com índice
SELECT * FROM Mede_Tempo_Q2($$
    SELECT name::TEXT, latitude, longitude, population 
    FROM cities 
    WHERE country_id = (SELECT id FROM countries WHERE code = 'BR' LIMIT 1)
      AND name LIKE 'São%';
$$);

-- Análise do plano de execução com o índice criado (deve demonstrar "Index Only Scan" ou "Index Scan")
EXPLAIN ANALYZE
SELECT name::TEXT, latitude, longitude, population 
FROM cities 
WHERE country_id = (SELECT id FROM countries WHERE code = 'BR' LIMIT 1)
  AND name LIKE 'São%';


-- ============================================================
-- EXERCÍCIO 3 – Questão Teórica: B-trees e LIKE com Curinga Inicial
-- ============================================================
/*
PERGUNTA:
Estruturas B-trees conseguem indexar consultas com predicados do tipo:
<Atributo> LIKE "%valor%" ? (Considere que o atributo seja do tipo TEXT). Explique.

RESPOSTA TEÓRICA DETALHADA:

Não, as estruturas B-tree tradicionais NÃO conseguem indexar eficientemente consultas com o curinga 
de porcentagem no início (do tipo '%valor%'). 

Explicação técnica:
1. Ordenação e Busca Binária:
   Uma B-tree organiza os dados de forma estritamente ordenada (alfabeticamente, no caso de TEXT).
   Isso permite que o mecanismo de busca do SGBD encontre elementos rapidamente (complexidade O(log N))
   através de busca binária a partir do início da string. Se buscamos por 'São%', o banco sabe exatamente 
   onde começar a ler na árvore (na primeira palavra com 'S') e onde terminar (quando as iniciais passarem de 'São').

2. O Problema do Curinga Inicial ('%'):
   Quando o padrão começa com '%', a string que buscamos pode começar com QUALQUER caractere 
   (ex: 'Ribeirão Preto', 'Campinas', 'Belo Horizonte'). Como o prefixo é desconhecido, o índice B-tree 
   perde completamente sua propriedade de ordenação útil para a pesquisa. 
   O otimizador de consultas do PostgreSQL não consegue fazer uma busca direcionada (Index Scan) 
   e é forçado a realizar uma varredura sequencial completa em todas as chaves do índice 
   (Index Full Scan / Index Scan em todas as tuplas) ou, mais frequentemente, varrer a própria tabela 
   (Seq Scan) aplicando a função de correspondência em cada linha.

3. Soluções Alternativas no PostgreSQL:
   Se a aplicação necessita de buscas textuais arbitrárias por substring (do tipo '%valor%') com alta performance, 
   o PostgreSQL oferece outras abordagens:
   
   - Extensão pg_trgm e Índices GIN/GiST:
     Podemos instalar a extensão nativa 'pg_trgm' (que divide o texto em trigramas de 3 caracteres)
     e criar um índice GIN (Generalized Inverted Index):
     
     CREATE EXTENSION IF NOT EXISTS pg_trgm;
     CREATE INDEX idx_cities_trgm ON cities USING gin (name gin_trgm_ops);
     
     Com o índice GIN de trigramas, o PostgreSQL consegue indexar perfeitamente e com excelente performance
     consultas que contenham LIKE '%valor%' ou buscas case-insensitive com ILIKE.
*/
