-- ============================================================
-- SCC-541 Laboratório de Bases de Dados – 2026
-- Trabalho Prático T4 – Exercícios sobre Visões (views)
-- Grupo: Katiely Feitosa de Lacerda   – 12777100
--        Leonardo Gonsalez            – 15657074
--        Miguel Filippo Calhabeu      – 15480331
--        Renan Silva Soriano          – 11794824
--        Guilherme Motta Tranche      – 13671549
-- ============================================================

-- ==============================================================
-- PRÉ-REQUISITOS: extensões para cálculo de distância geográfica
-- ==============================================================
CREATE EXTENSION IF NOT EXISTS cube;
CREATE EXTENSION IF NOT EXISTS earthdistance;

-- Reset para idempotência: restaura o estado original do(s) aeroporto(s)
-- corrigidos pelo Exercício 5, para que os Exercícios 2 e 4 produzam
-- resultados corretos em re-execuções do script.
UPDATE airports SET city_id = NULL WHERE ident = 'BR-0017';

-- ============================================================
-- EXERCÍCIO 1 – Visão materializada Aeroportos_Brasileiros
-- ============================================================

-- (a) Criação da visão materializada
DROP MATERIALIZED VIEW IF EXISTS Aeroportos_Brasileiros;

CREATE MATERIALIZED VIEW Aeroportos_Brasileiros AS
    SELECT
        a.name              AS aeroporto_nome,
        a.latitude_deg,
        a.longitude_deg,
        co.name             AS pais_nome,
        cont.name           AS continente,
        ci.name             AS cidade_nome,
        ci.population       AS cidade_populacao
    FROM airports a
    JOIN cities    ci   ON ci.id   = a.city_id
    JOIN countries co   ON co.id   = ci.country_id
    JOIN continents cont ON cont.id = co.continent_id
    WHERE co.code = 'BR';

-- Exemplo: primeiras 10 tuplas
SELECT * FROM Aeroportos_Brasileiros LIMIT 10;

-- Número total de tuplas
SELECT COUNT(*) AS total_aeroportos_brasileiros FROM Aeroportos_Brasileiros;

-- ------------------------------------------------------------------
-- (b) Comparação de desempenho: visão materializada vs consulta direta
-- ------------------------------------------------------------------

-- Consulta equivalente diretamente nas tabelas-base (para comparação de tempo)
EXPLAIN ANALYZE
SELECT
    a.name          AS aeroporto_nome,
    a.latitude_deg,
    a.longitude_deg,
    co.name         AS pais_nome,
    co.continent_id    AS continente,
    ci.name         AS cidade_nome,
    ci.population   AS cidade_populacao
FROM airports a
JOIN cities   ci ON ci.id   = a.city_id
JOIN countries co ON co.id  = ci.country_id
WHERE co.code = 'BR';

-- Consulta pela visão materializada (deve ser mais rápida)
EXPLAIN ANALYZE
SELECT * FROM Aeroportos_Brasileiros;

-- Consumo de armazenamento da visão materializada
SELECT
    pg_size_pretty(pg_total_relation_size('aeroportos_brasileiros')) AS tamanho_visao_mat;

-- ------------------------------------------------------------------
-- (c) Demonstração da necessidade de REFRESH
-- ------------------------------------------------------------------

-- Inserção de aeroporto fictício no Brasil
INSERT INTO airports (id, ident, airport_type_id, name, latitude_deg, longitude_deg, city_id)
VALUES (9990001, 'SBXX', 1, 'Aeroporto Fictício T4 – São Carlos', -22.0, -47.9,
        (SELECT id FROM cities WHERE name = 'São Carlos' AND country_id =
            (SELECT id FROM countries WHERE code = 'BR') LIMIT 1));

-- A visão materializada ainda NÃO mostra o novo aeroporto
SELECT COUNT(*) AS antes_do_refresh FROM Aeroportos_Brasileiros WHERE aeroporto_nome LIKE '%T4%';

-- Após o REFRESH, a visão é atualizada
REFRESH MATERIALIZED VIEW Aeroportos_Brasileiros;

SELECT COUNT(*) AS apos_o_refresh  FROM Aeroportos_Brasileiros WHERE aeroporto_nome LIKE '%T4%';

-- Limpeza do aeroporto fictício
DELETE FROM airports WHERE id = 9990001;
REFRESH MATERIALIZED VIEW Aeroportos_Brasileiros;


-- ============================================================
-- EXERCÍCIO 2 – Aeroportos_sem_cidades, Cidades_brasileiras
--               e associação por distância ≤ 10 km
-- =============================================================
CREATE EXTENSION IF NOT EXISTS cube;
CREATE EXTENSION IF NOT EXISTS earthdistance;
-- Visão: aeroportos sem cidade vinculada
DROP VIEW IF EXISTS Aeroportos_sem_cidades CASCADE;
CREATE VIEW Aeroportos_sem_cidades AS
    SELECT id, name, latitude_deg, longitude_deg
    FROM airports
    WHERE city_id IS NULL;

-- Visão: cidades brasileiras com população ≥ 100 000 habitantes
DROP VIEW IF EXISTS Cidades_brasileiras CASCADE;
CREATE VIEW Cidades_brasileiras AS
    SELECT ci.id, ci.name, ci.population, ci.latitude, ci.longitude
    FROM cities ci
    JOIN countries co ON co.id = ci.country_id
    WHERE co.code = 'BR'
      AND ci.population >= 100000;

-- Associação: aeroportos sem cidade × cidades brasileiras a ≤ 10 km
-- Usa CTE para isolar o cálculo da distância
WITH distancias AS (
    SELECT
        a.name                                              AS aeroporto_nome,
        c.name                                             AS cidade_nome,
        c.population                                       AS populacao,
        earth_distance(
            ll_to_earth(a.latitude_deg, a.longitude_deg),
            ll_to_earth(c.latitude,     c.longitude)
        ) / 1000.0                                         AS distancia_km
    FROM Aeroportos_sem_cidades a
    CROSS JOIN Cidades_brasileiras c
)
SELECT aeroporto_nome, cidade_nome, populacao,
       ROUND(distancia_km::numeric, 3) AS distancia_km
FROM distancias
WHERE distancia_km <= 10
ORDER BY aeroporto_nome, distancia_km;


-- ============================================================
-- EXERCÍCIO 3 – Visão Circuitos_completa
-- ============================================================

DROP VIEW IF EXISTS Circuitos_completa;
CREATE VIEW Circuitos_completa AS
    SELECT
        ci.name         AS circuito_nome,
        ci.lat,
        ci.long,
        ct.name         AS cidade_nome,
        co.name         AS pais_nome,
        co.code         AS pais_code,
        cont.name       AS continente_nome
    FROM circuits ci
    -- LEFT JOIN para incluir circuitos sem cidade vinculada
    LEFT JOIN cities     ct   ON ct.id   = ci.city_id
    LEFT JOIN countries  co   ON co.id   = ct.country_id
    LEFT JOIN continents cont ON cont.id = co.continent_id;

-- Número de tuplas
SELECT COUNT(*) AS total_circuitos FROM Circuitos_completa;

-- Exemplo variado: primeiras 10 tuplas
SELECT * FROM Circuitos_completa LIMIT 10;


-- ============================================================
-- EXERCÍCIO 4 – Visão Problemas_aeroportos
-- ============================================================

DROP VIEW IF EXISTS Problemas_aeroportos CASCADE;
CREATE VIEW Problemas_aeroportos AS
    WITH distancias AS (
        SELECT
            a.id                AS aeroporto_id,
            a.name              AS aeroporto_nome,
            a.latitude_deg,
            a.longitude_deg,
            c.name              AS cidade_candidata,
            c.population        AS populacao_candidata,
            earth_distance(
                ll_to_earth(a.latitude_deg, a.longitude_deg),
                ll_to_earth(c.latitude,     c.longitude)
            ) / 1000.0          AS distancia_km
        FROM Aeroportos_sem_cidades a
        CROSS JOIN Cidades_brasileiras c
    )
    SELECT
        aeroporto_id        AS id,
        aeroporto_nome      AS name,
        latitude_deg,
        longitude_deg,
        cidade_candidata,
        populacao_candidata AS populacao,
        ROUND(distancia_km::numeric, 3) AS distancia_km
    FROM distancias
    WHERE distancia_km <= 10;

-- Exemplo: primeiras tuplas da visão
SELECT * FROM Problemas_aeroportos ORDER BY name, distancia_km LIMIT 10;

-- (b) Por que esses aeroportos aparecem?
-- Esses aeroportos possuem city_id NULL na tabela airports, mas existem
-- cidades brasileiras com ≥ 100 000 hab. a menos de 10 km de suas
-- coordenadas geográficas, indicando possível vínculo não registrado.


-- ============================================================
-- EXERCÍCIO 5 – Visão Correcao_aeroportos e UPDATE via visão
-- ============================================================

DROP VIEW IF EXISTS Correcao_aeroportos;
CREATE VIEW Correcao_aeroportos AS
    SELECT id, name, latitude_deg, longitude_deg, city_id
    FROM airports
    WHERE id IN (SELECT DISTINCT id FROM Problemas_aeroportos);

-- Salvar IDs antes do UPDATE (Correcao_aeroportos esvaziará após a correção)
DROP TABLE IF EXISTS ids_corrigidos;
CREATE TEMP TABLE ids_corrigidos AS
    SELECT DISTINCT id FROM Problemas_aeroportos;

-- Identificar, para cada aeroporto, a cidade mais próxima (menor distância)
-- e atualizar city_id via UPDATE na visão (Correcao_aeroportos é atualizável:
-- deriva diretamente de airports sem agregações).

WITH cidade_mais_proxima AS (
    SELECT DISTINCT ON (id)
        id              AS aeroporto_id,
        cidade_candidata,
        distancia_km,
        -- Precisamos do id da cidade para o UPDATE
        (SELECT c.id
         FROM cities c
         JOIN countries co ON co.id = c.country_id
         WHERE co.code = 'BR'
           AND c.name  = p.cidade_candidata
         LIMIT 1)       AS cidade_id
    FROM Problemas_aeroportos p
    ORDER BY id, distancia_km
)
UPDATE Correcao_aeroportos ca
SET city_id = cmp.cidade_id
FROM cidade_mais_proxima cmp
WHERE ca.id = cmp.aeroporto_id
  AND cmp.cidade_id IS NOT NULL;

-- Verificar que os aeroportos corrigidos não aparecem mais em Aeroportos_sem_cidades
SELECT COUNT(*) AS aeroportos_sem_cidade_restantes FROM Aeroportos_sem_cidades
WHERE id IN (SELECT id FROM Correcao_aeroportos);

-- Consulta final para confirmar as correções realizadas
-- (usa airports diretamente; Correcao_aeroportos está vazia após a correção)
SELECT a.id, a.name, a.city_id, ci.name AS cidade_vinculada
FROM airports a
JOIN cities ci ON ci.id = a.city_id
WHERE a.id IN (SELECT id FROM ids_corrigidos)
ORDER BY a.name
LIMIT 20;
