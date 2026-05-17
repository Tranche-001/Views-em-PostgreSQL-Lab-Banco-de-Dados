/* ============================================================================================================
   CARGA - BASE FÓRMULA 1 + DADOS GEOGRÁFICOS
   ============================================================================================================

   OBJETIVO:
   Carregar dados da Fórmula 1 (circuits, drivers, constructors, races, results, etc.) e dados
   geográficos complementares (países, cidades, aeroportos) de forma consistente e performática.

   ESTRATÉGIA GERAL:
   - Usa tabelas STAGING temporárias para validação e transformação antes da carga final
     (Staging: área intermediária para processar dados antes de inserir na base principal)
   - Suporte a re-execução (idempotente) com tratamento de conflitos
     (Idempotente: script pode ser executado várias vezes sem problemas, usando ON CONFLICT)
   - Ordem de carga: dimensões primeiro (geográficas e F1), depois fatos (corridas, resultados)

   CONCEITOS IMPORTANTES PARA ALUNOS:
   - STAGING TABLES: Tabelas temporárias que armazenam dados brutos dos arquivos CSV/TSV.
     Permitem limpeza e validação antes de inserir na base final.
   - IDEMPOTÊNCIA: Propriedade que permite executar o script múltiplas vezes sem duplicatas.
   - FOREIGN KEYS (FK): Chaves estrangeiras garantem integridade referencial entre tabelas.
   - JOINs: Operações para combinar dados de múltiplas tabelas baseadas em chaves comuns.
   - ON CONFLICT: Trata conflitos de inserção (ex.: dados já existentes) sem erro.

   EXECUÇÃO:
   psql -h <host> -U <usuario> -d <banco> -f carga.sql

   ARQUIVOS DE ENTRADA (diretório: dados/labbd2026/):
   - circuits.csv: Autódromos da F1 (circuits)
   - constructors.csv: Escuderias (constructors)
   - drivers.csv: Pilotos (drivers)
   - races.csv: Corridas por temporada (races)
   - results.csv: Resultados das corridas (results)
   - qualifying.csv: Tempos de qualificação (qualifying)
   - driver_standings.csv: Classificação de pilotos (driver_standings)
   - constructor_standings.csv: Classificação de construtores (constructor_standings)
   - airports.csv: Aeroportos mundiais (airports)
   - countries.csv: Países (countries)
   - cities15000.tsv: Cidades principais (>15k habitantes) do GeoNames
   - timeZones.tsv: Fusos horários mundiais
   - featureCodes_en.tsv: Códigos de características geográficas (ex.: PPL = cidade)
   - iso-languagecodes.tsv: Códigos de idiomas ISO (ex.: pt = Portuguese)
============================================================================================================ */

-- Início da transação: Agrupa todas as operações em uma unidade atômica
-- Se algo falhar, tudo é desfeito (ROLLBACK automático)
BEGIN;

-- Configurações de sessão para performance e consistência
SET client_encoding = 'UTF8';  -- Define codificação UTF-8 para suportar acentos e caracteres especiais
SET datestyle TO ISO, YMD;     -- Formato de data: YYYY-MM-DD (padrão ISO)

-- ============================================================================================================
-- 1. LIMPEZA DO AMBIENTE
-- ============================================================================================================

-- Remove tabelas temporárias de execuções anteriores (se existirem)
-- IMPORTANTE: Garante que o script seja idempotente (pode ser executado várias vezes)
-- DROP IF EXISTS: Evita erro se a tabela não existir, permitindo re-execução segura
DROP TABLE IF EXISTS stg_circuits;
DROP TABLE IF EXISTS stg_constructors;
DROP TABLE IF EXISTS stg_drivers;
DROP TABLE IF EXISTS stg_races;
DROP TABLE IF EXISTS stg_driver_standings;
DROP TABLE IF EXISTS stg_constructor_standings;
DROP TABLE IF EXISTS stg_results;
DROP TABLE IF EXISTS stg_qualifying;
DROP TABLE IF EXISTS stg_airports;
DROP TABLE IF EXISTS stg_countries;
DROP TABLE IF EXISTS stg_time_zones;
DROP TABLE IF EXISTS stg_feature_codes;
DROP TABLE IF EXISTS stg_iso_language_codes;
DROP TABLE IF EXISTS stg_cities;

-- Tabelas temporárias auxiliares para processamento de standings
-- Usadas para resolver referências antes de inserir na base final
DROP TABLE IF EXISTS tmp_driver_standings_resolved;
DROP TABLE IF EXISTS tmp_constructor_standings_resolved;

-- ============================================================================================================
-- 2. CRIAÇÃO DAS TABELAS STAGING
-- ============================================================================================================

-- ESTRATÉGIA: Usar tabelas TEMPORÁRIAS (staging) para processamento intermediário
-- VANTAGENS:
-- - Validação e limpeza de dados antes da carga final (ex.: remover duplicatas)
-- - Isolamento de transação: Dados são descartados automaticamente se a transação falhar
-- - Performance: Não gera logs de transação (WAL), mais rápido para grandes volumes
-- - Flexibilidade: Permite transformação de dados (ex.: conversões de tipo)
-- TIPOS DE DADOS: Usamos TEXT para flexibilidade (aceita qualquer string), DOUBLE PRECISION para coordenadas

-- Dados da Fórmula 1 (F1)
CREATE TEMP TABLE stg_circuits (
    circuit_id      TEXT,           -- ID único do circuito (chave natural dos dados F1)
    name            TEXT,           -- Nome completo do autódromo
    lat             DOUBLE PRECISION, -- Latitude em graus decimais (coordenada geográfica)
    long            DOUBLE PRECISION, -- Longitude em graus decimais
    locality        TEXT,           -- Cidade ou localidade onde fica o circuito
    country         TEXT,           -- País (nome completo ou código)
    wikipedia_url   TEXT            -- Link para página da Wikipedia (opcional)
);

CREATE TEMP TABLE stg_constructors (
    constructor_id  TEXT,           -- ID único da escuderia (ex.: ferrari, mercedes)
    name            TEXT,           -- Nome oficial da escuderia
    nationality     TEXT,           -- Nacionalidade principal (ex.: Italian, German)
    wikipedia_url   TEXT            -- Link da Wikipedia da escuderia
);

CREATE TEMP TABLE stg_drivers (
    driver_id       TEXT,           -- ID único do piloto (ex.: hamilton, verstappen)
    givenname       TEXT,           -- Primeiro nome do piloto
    familyname      TEXT,           -- Sobrenome do piloto
    nationality     TEXT,           -- Nacionalidade do piloto
    dob             DATE            -- Data de nascimento (formato YYYY-MM-DD)
);

CREATE TEMP TABLE stg_races (
    race_id         TEXT,           -- ID único da corrida
    season          INTEGER,        -- Ano da temporada
    round           INTEGER,        -- Rodada do campeonato
    race_name       TEXT,           -- Nome da corrida
    date            DATE,           -- Data da corrida
    time            TEXT,           -- Hora da corrida
    circuit_id      TEXT            -- ID do circuito
);

CREATE TEMP TABLE stg_driver_standings (
    load_id         BIGSERIAL PRIMARY KEY, -- Sequencial para ordenação
    season          INTEGER,        -- Temporada
    round           INTEGER,        -- Rodada
    driver_id       TEXT,           -- ID do piloto
    position        INTEGER,        -- Posição
    points          NUMERIC(10,2),  -- Pontos acumulados
    wins            INTEGER         -- Vitórias
);

CREATE TEMP TABLE stg_constructor_standings (
    load_id         BIGSERIAL PRIMARY KEY, -- Sequencial para ordenação
    season          INTEGER,        -- Temporada
    round           INTEGER,        -- Rodada
    constructor_id  TEXT,           -- ID da escuderia
    position        NUMERIC,        -- Posição (pode ser decimal)
    points          NUMERIC(10,2),  -- Pontos acumulados
    wins            INTEGER         -- Vitórias
);

CREATE TEMP TABLE stg_results (
    race_id         TEXT,           -- ID da corrida
    driver_id       TEXT,           -- ID do piloto
    constructor_id  TEXT,           -- ID da escuderia
    grid            INTEGER,        -- Posição no grid
    position        VARCHAR(5),     -- Posição final (pode ter letras)
    position_order  INTEGER,        -- Ordem de chegada
    points          NUMERIC(10,2),  -- Pontos ganhos
    laps            INTEGER,        -- Voltas completadas
    status          TEXT            -- Status final (Finished, DNF, etc.)
);

CREATE TEMP TABLE stg_qualifying (
    race_id         TEXT,           -- ID da corrida
    driver_id       TEXT,           -- ID do piloto
    constructor_id  TEXT,           -- ID da escuderia
    position        NUMERIC,        -- Posição na qualificação
    q1              TEXT,           -- Tempo Q1
    q2              TEXT,           -- Tempo Q2
    q3              TEXT            -- Tempo Q3
);

CREATE TEMP TABLE stg_airports (
    id                  INTEGER,    -- ID sequencial do aeroporto
    ident               TEXT,       -- Código identificador único (ICAO ou IATA)
    type                TEXT,       -- Tipo de aeroporto (large_airport, medium_airport, etc.)
    name                TEXT,       -- Nome completo do aeroporto
    latitude_deg        DOUBLE PRECISION, -- Latitude em graus decimais
    longitude_deg       DOUBLE PRECISION, -- Longitude em graus decimais
    elevation_ft        INTEGER,    -- Elevação em pés acima do nível do mar
    continent           TEXT,       -- Continente (código: EU, AS, etc.)
    iso_country         TEXT,       -- Código ISO do país (2 letras)
    iso_region          TEXT,       -- Código da região administrativa (ex.: BR-SP)
    municipality        TEXT,       -- Município/cidade onde fica o aeroporto
    scheduled_service   TEXT,       -- Indica se há voos comerciais regulares
    icao_code           TEXT,       -- Código ICAO (4 letras, ex.: SBGR)
    iata_code           TEXT,       -- Código IATA (3 letras, ex.: GRU)
    gps_code            TEXT,       -- Código GPS adicional
    local_code          TEXT,       -- Código local específico
    home_link           TEXT,       -- Site oficial do aeroporto
    wikipedia_link      TEXT,       -- Página da Wikipedia
    keywords            TEXT        -- Palavras-chave para busca
);

CREATE TEMP TABLE stg_countries (
    id              INTEGER,        -- ID sequencial do país
    code            TEXT,           -- Código ISO 3166-1 alpha-2 (2 letras, ex.: BR)
    name            TEXT,           -- Nome oficial do país
    continent       TEXT,           -- Código do continente (AF, EU, AS, etc.)
    wikipedia_link  TEXT,           -- Link da Wikipedia do país
    keywords        TEXT            -- Termos alternativos para matching (ex.: Brazil, Brasil)
);

CREATE TEMP TABLE stg_time_zones (
    country_code    TEXT,           -- Código ISO do país associado
    time_zone_name  TEXT,           -- Nome do fuso horário (ex.: America/Sao_Paulo)
    gmt_offset      NUMERIC(10,2),  -- Diferença em horas do GMT atual
    dst_offset      NUMERIC(10,2),  -- Offset adicional no horário de verão
    raw_offset      NUMERIC(10,2)   -- Offset base sem DST
);

CREATE TEMP TABLE stg_feature_codes (
    full_code       TEXT,           -- Código completo (ex.: P.PPL para cidade populada)
    name            TEXT,           -- Nome da característica geográfica
    description     TEXT            -- Descrição detalhada
);

CREATE TEMP TABLE stg_iso_language_codes (
    iso_639_3       TEXT,           -- Código ISO 639-3 (mais específico, 3 letras)
    iso_639_2       TEXT,           -- Código ISO 639-2 (bibliotecário, 3 letras)
    iso_639_1       TEXT,           -- Código ISO 639-1 (mais comum, 2 letras, ex.: pt)
    language_name   TEXT            -- Nome completo do idioma (ex.: Portuguese)
);

CREATE TEMP TABLE stg_cities (
    geoname_id          BIGINT,     -- ID único do GeoNames (chave natural)
    name                TEXT,       -- Nome principal da cidade (com acentos)
    ascii_name          TEXT,       -- Nome sem acentos (para busca)
    alternate_names     TEXT,       -- Nomes alternativos separados por vírgula
    latitude            DOUBLE PRECISION, -- Latitude WGS84
    longitude           DOUBLE PRECISION, -- Longitude WGS84
    feature_class       TEXT,       -- Classe da característica (P = Populated Place)
    feature_code        TEXT,       -- Código específico (PPL = populated place)
    country_code        TEXT,       -- Código ISO do país
    cc2                 TEXT,       -- Código alternativo do país
    admin1_code         TEXT,       -- Código administrativo nível 1 (estado/província)
    admin2_code         TEXT,       -- Código administrativo nível 2 (município)
    admin3_code         TEXT,       -- Código administrativo nível 3
    admin4_code         TEXT,       -- Código administrativo nível 4
    population          BIGINT,     -- População estimada
    elevation           INTEGER,    -- Elevação em metros
    dem                 INTEGER,    -- Modelo Digital de Elevação (DEM)
    time_zone_name      TEXT,       -- Fuso horário associado
    modification_date   DATE        -- Data da última atualização no GeoNames
);

-- ============================================================================================================
-- 3. CARGA BRUTA DOS ARQUIVOS PARA STAGING
-- ============================================================================================================

-- ESTRATÉGIA: Carregar dados brutos dos arquivos CSV/TSV para tabelas staging
-- POR QUE ASSIM?
-- - \copy é mais eficiente que INSERT para grandes volumes (carrega diretamente)
-- - Dados ficam disponíveis para validação e transformação antes da carga final
-- - Permite detectar problemas (ex.: encoding, delimitadores) separadamente
-- - Permite pegar os dados locais, evitando transferências desnecessárias para o servidor
-- OPÇÕES DO \copy:
-- - FORMAT csv: Indica que é arquivo CSV (comma-separated values)
-- - HEADER true: Primeira linha é cabeçalho (nomes das colunas)
-- - ENCODING 'LATIN1': Para circuits.csv (dados antigos podem ter encoding diferente)
-- - DELIMITER E'\t': Para TSV (tab-separated), E'\t' é tabulação
-- - HEADER false: Alguns arquivos não têm cabeçalho

-- - /dados/ é o caminho local onde os arquivos estão armazenados (ajustar conforme necessário)

-- Carregar dados da Fórmula 1 (F1) para staging
\copy stg_circuits              FROM '/dados/circuits.csv'                 WITH (FORMAT csv, HEADER true, ENCODING 'LATIN1')
\copy stg_constructors          FROM '/dados/constructors.csv'             WITH (FORMAT csv, HEADER true)
\copy stg_drivers               FROM '/dados/drivers.csv'                  WITH (FORMAT csv, HEADER true)
\copy stg_races                 FROM '/dados/races.csv'                    WITH (FORMAT csv, HEADER true)
\copy stg_driver_standings      (season, round, driver_id, position, points, wins)      FROM '/dados/driver_standings.csv'      WITH (FORMAT csv, HEADER true)
\copy stg_constructor_standings (season, round, constructor_id, position, points, wins) FROM '/dados/constructor_standings.csv' WITH (FORMAT csv, HEADER true)
\copy stg_results               FROM '/dados/results.csv'                  WITH (FORMAT csv, HEADER true)
\copy stg_qualifying            FROM '/dados/qualifying.csv'               WITH (FORMAT csv, HEADER true)

-- Carregar dados geográficos complementares para staging
\copy stg_airports              FROM '/dados/airports.csv'                 WITH (FORMAT csv, HEADER true)
\copy stg_countries             FROM '/dados/countries.csv'                WITH (FORMAT csv, HEADER true)
\copy stg_time_zones            FROM '/dados/timeZones.tsv'                WITH (FORMAT csv, HEADER true, DELIMITER E'\t')
\copy stg_feature_codes         FROM '/dados/featureCodes_en.tsv'          WITH (FORMAT csv, HEADER false, DELIMITER E'\t')
\copy stg_iso_language_codes    FROM '/dados/iso-languagecodes.tsv'        WITH (FORMAT csv, HEADER true, DELIMITER E'\t')
\copy stg_cities                FROM '/dados/cities.tsv'                   WITH (FORMAT csv, HEADER false, DELIMITER E'\t')
-- ============================================================================================================
-- 4. CARGA GEOGRÁFICA - DIMENSÕES BASE
-- ============================================================================================================

-- ESTRATÉGIA: Carregar dimensões geográficas PRIMEIRO
-- POR QUE? Entidades F1 (ex.: circuitos) referenciam países/cidades, então estas devem existir antes
-- ORDEM: Continentes → Países → Idiomas → Características → Cidades → Aeroportos

-- Continentes: Mapeamento de códigos (AF, EU) para nomes completos
-- Usa CASE para traduzir códigos em nomes legíveis
INSERT INTO continents (code, name)
SELECT DISTINCT
    c.continent,
    CASE c.continent
        WHEN 'AF' THEN 'Africa'
        WHEN 'AN' THEN 'Antarctica'
        WHEN 'AS' THEN 'Asia'
        WHEN 'EU' THEN 'Europe'
        WHEN 'NA' THEN 'North America'
        WHEN 'OC' THEN 'Oceania'
        WHEN 'SA' THEN 'South America'
        ELSE c.continent  -- Mantém código se não reconhecido
    END
FROM stg_countries c
WHERE c.continent IS NOT NULL
ON CONFLICT (code) DO NOTHING;  -- Evita duplicatas se re-executar

-- Países (com relacionamento para continentes)
INSERT INTO countries (code, name, wikipedia_link, keywords, continent_id)
SELECT
    s.code,
    s.name,
    s.wikipedia_link,
    s.keywords,
    ct.id
FROM stg_countries s
JOIN continents ct
    ON ct.code = s.continent
ON CONFLICT (code) DO UPDATE
SET name = EXCLUDED.name,
    wikipedia_link = EXCLUDED.wikipedia_link,
    keywords = EXCLUDED.keywords,
    continent_id = EXCLUDED.continent_id;

-- Fusos horários
INSERT INTO time_zones (name, gmt_offset, dst_offset, raw_offset)
SELECT DISTINCT
    s.time_zone_name,
    s.gmt_offset,
    s.dst_offset,
    s.raw_offset
FROM stg_time_zones s
WHERE s.time_zone_name IS NOT NULL
ON CONFLICT (name) DO NOTHING;

-- Nomes de idiomas (base para códigos ISO)
INSERT INTO language_names (name)
SELECT DISTINCT TRIM(s.language_name)
FROM stg_iso_language_codes s
WHERE TRIM(s.language_name) <> ''
ON CONFLICT (name) DO NOTHING;

-- Códigos ISO de idiomas
INSERT INTO iso_language_codes (iso_639_3, iso_639_2, iso_639_1, language_id)
SELECT
    NULLIF(TRIM(s.iso_639_3), ''),
    NULLIF(TRIM(s.iso_639_2), ''),
    NULLIF(TRIM(s.iso_639_1), ''),
    ln.id
FROM stg_iso_language_codes s
JOIN language_names ln
    ON ln.name = TRIM(s.language_name)
ON CONFLICT DO NOTHING;

-- Códigos de características geográficas (PPL = populated place, etc.)
INSERT INTO feature_codes (feature_class, feature_code, name, description)
SELECT DISTINCT
    split_part(s.full_code, '.', 1),
    split_part(s.full_code, '.', 2),
    s.name,
    s.description
FROM stg_feature_codes s
WHERE s.full_code IS NOT NULL
  AND position('.' IN s.full_code) > 0
ON CONFLICT (feature_class, feature_code) DO NOTHING;

-- ============================================================================================================
-- 5. CIDADES PRINCIPAIS (GeoNames - cidades >15k habitantes)
-- ============================================================================================================

-- Estratégia: Carregar cidades do GeoNames primeiro (fonte autoritativa)
-- Regras de deduplicação:
-- 1. Priorizar por geoname_id único (chave natural)
-- 2. Evitar duplicatas por nome + país (case-insensitive)
-- 3. Usar LEFT JOINs para dados opcionais (feature_codes, time_zones)

INSERT INTO cities (
    id,
    name,
    ascii_name,
    alternate_names,
    latitude,
    longitude,
    feature_code_id,
    country_id,
    time_zone_id,
    cc2,
    admin1_code,
    admin2_code,
    admin3_code,
    admin4_code,
    population,
    elevation,
    dem,
    modification_date
)
SELECT
    s.geoname_id,
    s.name,
    s.ascii_name,
    s.alternate_names,
    s.latitude,
    s.longitude,
    fc.id,
    c.id,
    tz.id,
    s.cc2,
    s.admin1_code,
    s.admin2_code,
    s.admin3_code,
    s.admin4_code,
    s.population,
    s.elevation,
    s.dem,
    s.modification_date
FROM stg_cities s
LEFT JOIN feature_codes fc
    ON fc.feature_class = s.feature_class
   AND fc.feature_code = s.feature_code
LEFT JOIN countries c
    ON c.code = s.country_code
LEFT JOIN time_zones tz
    ON tz.name = s.time_zone_name
WHERE c.id IS NOT NULL  -- Só inserir se o país existir
ON CONFLICT (id) DO NOTHING;  -- Evitar duplicatas por geoname_id

-- Ajustar sequence para próximos IDs gerados automaticamente
SELECT setval(
    pg_get_serial_sequence('cities', 'id'),
    COALESCE((SELECT MAX(id) FROM cities), 1)
);

-- ============================================================================================================
-- 6. CIDADES COMPLEMENTARES VIA AEROPORTOS
-- ============================================================================================================

INSERT INTO cities (
    name,
    ascii_name,
    latitude,
    longitude,
    country_id
)
SELECT DISTINCT
    trim(s.municipality) AS name,
    trim(s.municipality) AS ascii_name,
    s.latitude_deg AS latitude,
    s.longitude_deg AS longitude,
    c.id AS country_id
FROM stg_airports s
JOIN countries c
    ON c.code = s.iso_country
WHERE s.municipality IS NOT NULL
  AND NOT EXISTS (
      SELECT 1
      FROM cities ci
      WHERE lower(trim(ci.name)) = lower(trim(s.municipality))
        AND ci.country_id = c.id
  );

-- ============================================================================================================
-- 7. CIDADES COMPLEMENTARES VIA CIRCUITOS F1
-- ============================================================================================================

INSERT INTO cities (
    name,
    ascii_name,
    latitude,
    longitude,
    country_id
)
SELECT DISTINCT
    trim(s.locality) AS name,
    trim(s.locality) AS ascii_name,
    s.lat AS latitude,
    s.long AS longitude,
    c.id AS country_id
FROM stg_circuits s
JOIN countries c
    ON lower(trim(c.name)) = lower(trim(s.country))
WHERE s.locality IS NOT NULL
  AND NOT EXISTS (
      SELECT 1
      FROM cities ci
      WHERE lower(trim(ci.name)) = lower(trim(s.locality))
        AND ci.country_id = c.id
  );

-- Tipos de aeroportos (dimensão para classificação)
INSERT INTO airport_types (type)
SELECT DISTINCT s.type
FROM stg_airports s
WHERE s.type IS NOT NULL
ON CONFLICT (type) DO NOTHING;

-- ============================================================================================================
-- 8. AEROPORTOS
-- ============================================================================================================

INSERT INTO airports (
    ident,
    airport_type_id,
    name,
    latitude_deg,
    longitude_deg,
    elevation_ft,
    city_id,
    scheduled_service,
    icao_code,
    iata_code,
    gps_code,
    local_code,
    home_link,
    wikipedia_link,
    keywords
)
SELECT
    s.ident,
    at.id,
    s.name,
    s.latitude_deg,
    s.longitude_deg,
    s.elevation_ft,
    ci.id,
    s.scheduled_service,
    s.icao_code,
    s.iata_code,
    s.gps_code,
    s.local_code,
    s.home_link,
    s.wikipedia_link,
    s.keywords
FROM stg_airports s
JOIN airport_types at
    ON at.type = s.type
LEFT JOIN countries co
    ON co.code = s.iso_country
LEFT JOIN cities ci
    ON lower(trim(ci.name)) = lower(trim(s.municipality))
    AND ci.country_id = co.id
ON CONFLICT (ident) DO NOTHING;

-- ============================================================================================================
-- 9. CARGA F1 - DIMENSÕES PRINCIPAIS
-- ============================================================================================================

-- Estratégia: Carregar dimensões F1 (tabelas de referência) antes dos fatos
-- para que chaves estrangeiras possam ser resolvidas

-- Temporadas (dimensão temporal)
INSERT INTO seasons (year)
SELECT DISTINCT season
FROM stg_races
WHERE season IS NOT NULL
ON CONFLICT (year) DO NOTHING;

-- Status de corrida (enumeração de resultados)
INSERT INTO status (status)
SELECT DISTINCT status
FROM stg_results
WHERE status IS NOT NULL
ON CONFLICT (status) DO NOTHING;

-- Escuderias
INSERT INTO constructors (
    constructor_ref,
    name,
    nationality,
    wikipedia_url
)
SELECT DISTINCT
    s.constructor_id,
    s.name,
    s.nationality,
    s.wikipedia_url
FROM stg_constructors s
ON CONFLICT (constructor_ref) DO NOTHING;

-- Pilotos
INSERT INTO drivers (
    driver_ref,
    given_name,
    family_name,
    nationality,
    date_of_birth
)
SELECT DISTINCT
    s.driver_id,
    s.givenname,
    s.familyname,
    s.nationality,
    s.dob
FROM stg_drivers s
ON CONFLICT (driver_ref) DO NOTHING;

-- Circuitos 
INSERT INTO circuits (
    circuit_ref,
    name,
    lat,
    long,
    city_id,
    wikipedia_url
)
SELECT DISTINCT
    s.circuit_id,
    s.name,
    s.lat,
    s.long,
    ci.id,
    s.wikipedia_url
FROM stg_circuits s
LEFT JOIN cities ci
    ON lower(trim(ci.name)) = lower(trim(s.locality))
LEFT JOIN countries co
    ON lower(trim(co.name)) = lower(trim(s.country))
ON CONFLICT (circuit_ref) DO NOTHING;

-- ============================================================================================================
-- 10. CARGA F1 - TABELAS TRANSACIONAIS (FATOS)
-- ============================================================================================================

-- Estratégia: Carregar fatos F1 após todas as dimensões estarem disponíveis
-- Todas as FKs são resolvidas via JOINs com tabelas de referência

-- Corridas (tabela central do modelo F1)
INSERT INTO races (
    race_ref,
    season_id,
    round,
    race_name,
    race_date,
    race_time,
    circuit_id
)
SELECT
    r.race_id,
    s.id,
    r.round,
    r.race_name,
    r.date,
    NULLIF(r.time, '')::TIME,  -- Converter string vazia para NULL
    c.id
FROM stg_races r
JOIN seasons s
    ON s.year = r.season
JOIN circuits c
    ON c.circuit_ref = r.circuit_id
ON CONFLICT (race_ref) DO NOTHING;

-- Qualificações (tempos de qualifying por piloto/corrida)
INSERT INTO qualifying (
    race_id,
    driver_id,
    constructor_id,
    position,
    q1,
    q2,
    q3
)
SELECT
    r.id,
    d.id,
    c.id,
    q.position,
    q.q1,
    q.q2,
    q.q3
FROM stg_qualifying q
JOIN races r
    ON r.race_ref = q.race_id
JOIN drivers d
    ON d.driver_ref = q.driver_id
JOIN constructors c
    ON c.constructor_ref = q.constructor_id
ON CONFLICT (race_id, driver_id) DO NOTHING;

-- Resultados das corridas (dados detalhados de cada piloto em cada corrida)
INSERT INTO results (
    race_id,
    driver_id,
    constructor_id,
    grid,
    position,
    position_order,
    points,
    laps,
    status_id
)
SELECT
    r.id,
    d.id,
    c.id,
    s.grid,
    s.position,
    s.position_order,
    s.points,
    s.laps,
    st.id
FROM stg_results s
JOIN races r
    ON r.race_ref = s.race_id
JOIN drivers d
    ON d.driver_ref = s.driver_id
JOIN constructors c
    ON c.constructor_ref = s.constructor_id
JOIN status st
    ON st.status = s.status
ON CONFLICT (race_id, driver_id) DO NOTHING;

-- ============================================================================================================
-- 12. CARGA F1 - STANDINGS (CLASSIFICAÇÕES) NORMALIZADOS
-- ============================================================================================================

-- ESTRATÉGIA COMPLEXA PARA STANDINGS (IMPORTANTE PARA ALUNOS):
-- PROBLEMA: Dados vêm em formato "plano" (season, round, driver, position, points, wins)
-- SOLUÇÃO: Normalizar para modelo relacional com duas tabelas:
--   - standings: Cabeçalho comum (season, round, position, points, wins)
--   - driver_standings/constructor_standings: Linhas específicas (referência ao cabeçalho + driver/constructor)
-- POR QUE? Evita duplicação de dados e permite extensibilidade
-- TÉCNICA: Usar bloco DO $$ com LOOP para processar sequencialmente
-- VANTAGEM: Garante integridade (cada standing tem ID único) e ordenação consistente

-- Etapa 1: Preparar tabela temporária com referências resolvidas (IDs numéricos)
-- JOIN com seasons e drivers para obter IDs em vez de códigos textuais
CREATE TEMP TABLE tmp_driver_standings_resolved AS
SELECT
    s.load_id,          -- Para ordenação consistente
    se.id AS season_id, -- ID da temporada (FK)
    s.round,            -- Rodada do campeonato
    s.position,         -- Posição na classificação
    s.points,           -- Pontos acumulados
    s.wins,             -- Número de vitórias
    d.id AS driver_id   -- ID do piloto (FK)
FROM stg_driver_standings s
JOIN seasons se
    ON se.year = s.season  -- Relaciona temporada por ano
JOIN drivers d
    ON d.driver_ref = s.driver_id;  -- Relaciona piloto por referência textual

-- Etapa 2: Processar driver standings sequencialmente usando bloco PL/pgSQL
-- POR QUE LOOP? Para inserir cabeçalho primeiro e obter ID, depois linha
DO $$
DECLARE
    rec RECORD;              -- Variável para armazenar cada linha processada
    v_standings_id INTEGER;  -- ID do standing recém-inserido (para FK)
BEGIN
    -- Loop por cada registro, ordenado por load_id para consistência
    FOR rec IN
        SELECT *
        FROM tmp_driver_standings_resolved
        ORDER BY load_id  -- Ordenação garante reprodutibilidade
    LOOP
        -- Inserir cabeçalho na tabela standings (dados comuns)
        INSERT INTO standings (season_id, round, position, points, wins)
        VALUES (rec.season_id, rec.round, rec.position::INTEGER, rec.points, rec.wins)
        RETURNING id INTO v_standings_id;  -- Captura o ID gerado

        -- Inserir linha específica na tabela driver_standings
        INSERT INTO driver_standings (standing_id, driver_id)
        VALUES (v_standings_id, rec.driver_id);
    END LOOP;
END $$;

-- Preparar dados de constructor standings resolvidos
CREATE TEMP TABLE tmp_constructor_standings_resolved AS
SELECT
    s.load_id,
    se.id AS season_id,
    s.round,
    s.position,
    s.points,
    s.wins,
    c.id AS constructor_id
FROM stg_constructor_standings s
JOIN seasons se
    ON se.year = s.season
JOIN constructors c
    ON c.constructor_ref = s.constructor_id;

-- Processar constructor standings sequencialmente
DO $$
DECLARE
    rec RECORD;
    v_standings_id INTEGER;
BEGIN
    FOR rec IN
        SELECT *
        FROM tmp_constructor_standings_resolved
        ORDER BY load_id  -- Ordenação consistente
    LOOP
        -- Inserir cabeçalho do standing
        INSERT INTO standings (season_id, round, position, points, wins)
        VALUES (rec.season_id, rec.round, rec.position::INTEGER, rec.points, rec.wins)
        RETURNING id INTO v_standings_id;

        -- Inserir linha do constructor standing
        INSERT INTO constructor_standings (standing_id, constructor_id)
        VALUES (v_standings_id, rec.constructor_id);
    END LOOP;
END $$;

-- ============================================================================================================
-- CARGA CONCLUÍDA COM SUCESSO
-- ============================================================================================================

-- Confirmar todas as operações da transação
-- COMMIT: Aplica definitivamente todas as mudanças no banco de dados
-- Se chegou aqui sem erros, todos os dados foram carregados com sucesso
COMMIT;