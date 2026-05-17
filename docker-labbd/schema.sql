/* ============================================================================================================
   SCHEMA V1 - BASE FÓRMULA 1 + DADOS GEOGRÁFICOS
   ============================================================================================================

   OBJETIVO:
   Criar o esquema relacional completo para armazenar dados da Fórmula 1 e informações geográficas
   complementares (países, cidades, aeroportos) de forma normalizada e consistente.

   PRINCÍPIOS DE DESIGN:
   - IDs auto-incrementais (SERIAL) para chaves primárias
   - Referências externas via campos "_ref" (ex: driver_ref, circuit_ref)
   - Constraints UNIQUE em campos de referência externa
   - Relacionamentos opcionais (LEFT JOINs) onde apropriado
   - Normalização de standings (tabela base + especializações)

   EXECUÇÃO:
   psql -h <host> -U <usuario> -d <banco> -f schema.sql
============================================================================================================ */

-- Configurações de sessão para consistência
SET client_encoding = 'UTF8';
SET datestyle TO ISO, YMD;

-- ============================================================================================================
-- 1. LIMPEZA DO AMBIENTE
-- ============================================================================================================

-- Estratégia: DROP CASCADE para remover dependências automaticamente
-- Ordem: Iniciar pelas tabelas que referenciam outras (folhas da árvore de dependências)

-- Tabelas F1 (dependem de dimensões geográficas)
DROP TABLE IF EXISTS constructor_standings CASCADE;
DROP TABLE IF EXISTS driver_standings CASCADE;
DROP TABLE IF EXISTS standings CASCADE;
DROP TABLE IF EXISTS qualifying CASCADE;
DROP TABLE IF EXISTS results CASCADE;
DROP TABLE IF EXISTS races CASCADE;
DROP TABLE IF EXISTS seasons CASCADE;
DROP TABLE IF EXISTS drivers CASCADE;
DROP TABLE IF EXISTS constructors CASCADE;
DROP TABLE IF EXISTS circuits CASCADE;
DROP TABLE IF EXISTS status CASCADE;

-- Tabelas geográficas
DROP TABLE IF EXISTS airports CASCADE;
DROP TABLE IF EXISTS airport_types CASCADE;
DROP TABLE IF EXISTS cities CASCADE;
DROP TABLE IF EXISTS country_languages CASCADE;
DROP TABLE IF EXISTS iso_language_codes CASCADE;
DROP TABLE IF EXISTS language_names CASCADE;
DROP TABLE IF EXISTS feature_codes CASCADE;
DROP TABLE IF EXISTS time_zones CASCADE;
DROP TABLE IF EXISTS countries CASCADE;
DROP TABLE IF EXISTS continents CASCADE;

-- ============================================================================================================
-- 2. DIMENSÕES GEOGRÁFICAS BÁSICAS
-- ============================================================================================================

-- Continentes (dimensão mais alta na hierarquia geográfica)
CREATE TABLE continents (
    id                  SERIAL PRIMARY KEY,
    code                VARCHAR(2) NOT NULL UNIQUE,  -- AF, EU, AS, etc.
    name                VARCHAR(100) NOT NULL UNIQUE -- Africa, Europe, Asia, etc.
);

COMMENT ON TABLE continents IS 'Continentes do mundo';
COMMENT ON COLUMN continents.code IS 'Código de 2 letras do continente';
COMMENT ON COLUMN continents.name IS 'Nome completo do continente';

-- Países (depende de continentes)
CREATE TABLE countries (
    id                  SERIAL PRIMARY KEY,
    code                VARCHAR(2) NOT NULL UNIQUE,  -- Código ISO 3166-1 alpha-2
    name                VARCHAR(255) NOT NULL UNIQUE, -- Nome oficial do país
    wikipedia_link      TEXT,                        -- Link da Wikipedia
    keywords            TEXT,                        -- Palavras-chave para busca
    continent_id        INTEGER NOT NULL,            -- Relacionamento com continente
    CONSTRAINT fk_countries_continent
        FOREIGN KEY (continent_id) REFERENCES continents(id)
);

COMMENT ON TABLE countries IS 'Países do mundo';
COMMENT ON COLUMN countries.code IS 'Código ISO 3166-1 alpha-2 do país';
COMMENT ON COLUMN countries.keywords IS 'Termos alternativos para busca e matching';

-- Fusos horários (independente, mas pode ser associado a países)
CREATE TABLE time_zones (
    id                  SERIAL PRIMARY KEY,
    name                VARCHAR(255) NOT NULL UNIQUE, -- Nome do fuso (ex: America/Sao_Paulo)
    gmt_offset          NUMERIC(10,2),               -- Offset GMT atual
    dst_offset          NUMERIC(10,2),               -- Offset horário de verão
    raw_offset          NUMERIC(10,2)                -- Offset bruto (sem DST)
);

COMMENT ON TABLE time_zones IS 'Fusos horários mundiais';
COMMENT ON COLUMN time_zones.gmt_offset IS 'Diferença em horas do GMT (Greenwich Mean Time)';
COMMENT ON COLUMN time_zones.raw_offset IS 'Offset base sem considerar horário de verão';

-- ============================================================================================================
-- 3. SUPORTE MULTILINGUE E GEOGRÁFICO
-- ============================================================================================================

-- Sistema de idiomas (suporte a múltiplos idiomas por país)
CREATE TABLE language_names (
    id                  SERIAL PRIMARY KEY,
    name                VARCHAR(255) NOT NULL UNIQUE -- Nome do idioma (ex: Portuguese, English)
);

COMMENT ON TABLE language_names IS 'Nomes padronizados dos idiomas';

CREATE TABLE iso_language_codes (
    id                  SERIAL PRIMARY KEY,
    iso_639_3           VARCHAR(10) UNIQUE,  -- Código de 3 letras (mais específico)
    iso_639_2           VARCHAR(10) UNIQUE,  -- Código de 3 letras (bibliotecário)
    iso_639_1           VARCHAR(10) UNIQUE,  -- Código de 2 letras (mais comum)
    language_id         INTEGER NOT NULL,   -- Referência ao nome do idioma
    CONSTRAINT fk_iso_language_codes_language
        FOREIGN KEY (language_id) REFERENCES language_names(id)
);

COMMENT ON TABLE iso_language_codes IS 'Códigos ISO 639 para idiomas';
COMMENT ON COLUMN iso_language_codes.iso_639_1 IS 'Código de 2 letras (mais usado)';
COMMENT ON COLUMN iso_language_codes.iso_639_3 IS 'Código de 3 letras (mais específico)';

-- Relacionamento muitos-para-muitos: países podem ter múltiplos idiomas
CREATE TABLE country_languages (
    country_id          INTEGER NOT NULL,
    language_id         INTEGER NOT NULL,
    PRIMARY KEY (country_id, language_id),
    CONSTRAINT fk_country_languages_country
        FOREIGN KEY (country_id) REFERENCES countries(id),
    CONSTRAINT fk_country_languages_language
        FOREIGN KEY (language_id) REFERENCES language_names(id)
);

COMMENT ON TABLE country_languages IS 'Relacionamento muitos-para-muitos entre países e idiomas';

-- Códigos de características geográficas (do GeoNames)
CREATE TABLE feature_codes (
    id                  SERIAL PRIMARY KEY,
    feature_class       CHAR(1) NOT NULL,           -- Classe (A=Admin, H=Hydro, etc.)
    feature_code        VARCHAR(20) NOT NULL,       -- Código específico (ADM1, LK, etc.)
    name                VARCHAR(255) NOT NULL,      -- Nome da característica
    description         TEXT,                       -- Descrição detalhada
    CONSTRAINT uq_feature_codes
        UNIQUE (feature_class, feature_code)
);

COMMENT ON TABLE feature_codes IS 'Códigos de características geográficas do GeoNames';
COMMENT ON COLUMN feature_codes.feature_class IS 'Classe da característica (A=Admin, H=Hydro, P=Populated Place, etc.)';
COMMENT ON COLUMN feature_codes.feature_code IS 'Código específico dentro da classe';

-- ============================================================================================================
-- 4. LOCALIDADES GEOGRÁFICAS
-- ============================================================================================================

-- Cidades (dados do GeoNames + complementos)
CREATE TABLE cities (
    id                  SERIAL PRIMARY KEY,
    name                VARCHAR(200) NOT NULL,      -- Nome principal da cidade
    ascii_name          VARCHAR(200),               -- Nome ASCII (sem acentos)
    alternate_names     TEXT,                       -- Nomes alternativos (separados por vírgula)
    latitude            DOUBLE PRECISION,           -- Latitude WGS84
    longitude           DOUBLE PRECISION,           -- Longitude WGS84
    feature_code_id     INTEGER,                    -- Tipo de localidade (opcional)
    country_id          INTEGER NOT NULL,           -- País da cidade
    time_zone_id        INTEGER,                    -- Fuso horário (opcional)
    cc2                 VARCHAR(200),               -- Código alternativo do país
    admin1_code         VARCHAR(20),                -- Código administrativo nível 1
    admin2_code         VARCHAR(80),                -- Código administrativo nível 2
    admin3_code         VARCHAR(20),                -- Código administrativo nível 3
    admin4_code         VARCHAR(20),                -- Código administrativo nível 4
    population          BIGINT,                     -- População
    elevation           INTEGER,                    -- Elevação em metros
    dem                 INTEGER,                    -- Modelo digital de elevação
    modification_date   DATE,                       -- Data da última modificação
    CONSTRAINT fk_cities_feature_code
        FOREIGN KEY (feature_code_id) REFERENCES feature_codes(id),
    CONSTRAINT fk_cities_time_zone
        FOREIGN KEY (time_zone_id) REFERENCES time_zones(id),
    CONSTRAINT fk_cities_country
        FOREIGN KEY (country_id) REFERENCES countries(id)
);

COMMENT ON TABLE cities IS 'Cidades e localidades geográficas';
COMMENT ON COLUMN cities.ascii_name IS 'Nome da cidade sem caracteres especiais/accentuação';
COMMENT ON COLUMN cities.alternate_names IS 'Nomes alternativos separados por vírgula';
COMMENT ON COLUMN cities.dem IS 'Modelo Digital de Elevação (DEM) em metros';

-- Tipos de aeroporto (dimensão para classificação)
CREATE TABLE airport_types (
    id                  SERIAL PRIMARY KEY,
    type                VARCHAR(100) NOT NULL UNIQUE -- large_airport, medium_airport, etc.
);

COMMENT ON TABLE airport_types IS 'Tipos de aeroporto (classificação por tamanho/tráfego)';

-- Aeroportos (dados de aviação civil)
CREATE TABLE airports (
    id                  SERIAL PRIMARY KEY,
    ident               VARCHAR(100) NOT NULL UNIQUE, -- Código identificador (ICAO/IATA)
    airport_type_id     INTEGER NOT NULL,           -- Tipo do aeroporto
    name                TEXT NOT NULL,              -- Nome completo
    latitude_deg        DOUBLE PRECISION,           -- Latitude
    longitude_deg       DOUBLE PRECISION,           -- Longitude
    elevation_ft        INTEGER,                    -- Elevação em pés
    city_id             INTEGER,                   -- Cidade associada
    scheduled_service   VARCHAR(10),               -- Serviço agendado (yes/no)
    icao_code           VARCHAR(10),               -- Código ICAO (4 letras)
    iata_code           VARCHAR(10),               -- Código IATA (3 letras)
    gps_code            VARCHAR(20),               -- Código GPS
    local_code          VARCHAR(20),               -- Código local
    home_link           TEXT,                      -- Site oficial
    wikipedia_link      TEXT,                      -- Página da Wikipedia
    keywords            TEXT,                      -- Palavras-chave
    CONSTRAINT fk_airports_type
        FOREIGN KEY (airport_type_id) REFERENCES airport_types(id),
    CONSTRAINT fk_airports_city
        FOREIGN KEY (city_id) REFERENCES cities(id)
);

COMMENT ON TABLE airports IS 'Aeroportos mundiais';
COMMENT ON COLUMN airports.ident IS 'Identificador único do aeroporto (geralmente ICAO ou IATA)';
COMMENT ON COLUMN airports.elevation_ft IS 'Elevação do aeroporto em pés acima do nível do mar';
COMMENT ON COLUMN airports.icao_code IS 'Código ICAO de 4 letras';
COMMENT ON COLUMN airports.iata_code IS 'Código IATA de 3 letras';

-- ============================================================================================================
-- 5. DIMENSÕES FÓRMULA 1
-- ============================================================================================================

-- Status de corrida (enumeração de ocorrências)
CREATE TABLE status (
    id                  SERIAL PRIMARY KEY,
    status              TEXT NOT NULL UNIQUE -- Descrição textual (Finished, DNF, etc.)
);

COMMENT ON TABLE status IS 'Status possíveis de uma corrida (Finished, DNF, Accident, etc.)';
COMMENT ON COLUMN status.status IS 'Descrição textual da ocorrência vinda de results.csv';

-- Temporadas (dimensão temporal)
CREATE TABLE seasons (
    id                  SERIAL PRIMARY KEY,
    year                INTEGER NOT NULL UNIQUE -- Ano da temporada (1950, 1951, etc.)
);

COMMENT ON TABLE seasons IS 'Temporadas da Fórmula 1';
COMMENT ON COLUMN seasons.year IS 'Ano da temporada de F1';

-- Circuitos (autódromos)
CREATE TABLE circuits (
    id                  SERIAL PRIMARY KEY,
    circuit_ref         VARCHAR(255) NOT NULL UNIQUE, -- ID externo (de circuits.csv)
    name                TEXT NOT NULL,               -- Nome completo do circuito
    lat                 DOUBLE PRECISION,            -- Latitude
    long                DOUBLE PRECISION,            -- Longitude
    city_id             INTEGER,                     -- Cidade do circuito
    wikipedia_url       TEXT,                        -- Link da Wikipedia
    CONSTRAINT fk_circuits_city
        FOREIGN KEY (city_id) REFERENCES cities(id)
);

COMMENT ON TABLE circuits IS 'Autódromos da Fórmula 1';
COMMENT ON COLUMN circuits.circuit_ref IS 'Identificador único vindo de circuits.csv';
COMMENT ON COLUMN circuits.lat IS 'Latitude do circuito em graus decimais';
COMMENT ON COLUMN circuits.long IS 'Longitude do circuito em graus decimais';

-- Escuderias/Construtores
CREATE TABLE constructors (
    id                  SERIAL PRIMARY KEY,
    constructor_ref     VARCHAR(255) NOT NULL UNIQUE,   -- ID externo (de constructors.csv)
    name                VARCHAR(255) NOT NULL UNIQUE,   -- Nome da escuderia
    nationality         VARCHAR(255) NOT NULL,          -- Gentílico principal
    wikipedia_url       TEXT                           -- Link da Wikipedia
);

COMMENT ON TABLE constructors IS 'Escuderias da Fórmula 1';
COMMENT ON COLUMN constructors.constructor_ref IS 'Identificador único vindo de constructors.csv';
COMMENT ON COLUMN constructors.name IS 'Nome oficial da escuderia';
COMMENT ON COLUMN constructors.nationality IS 'Gentílico principal da escuderia';

-- Pilotos
CREATE TABLE drivers (
    id                  SERIAL PRIMARY KEY,
    driver_ref          VARCHAR(255) NOT NULL UNIQUE, -- ID externo (de drivers.csv)
    given_name          VARCHAR(255) NOT NULL,       -- Primeiro nome
    family_name         VARCHAR(255) NOT NULL,       -- Sobrenome
    nationality         VARCHAR(255) NOT NULL,       -- Gentílico principal
    date_of_birth       DATE                         -- Data de nascimento
);

COMMENT ON TABLE drivers IS 'Pilotos da Fórmula 1';
COMMENT ON COLUMN drivers.driver_ref IS 'Identificador único vindo de drivers.csv';
COMMENT ON COLUMN drivers.given_name IS 'Primeiro nome do piloto';
COMMENT ON COLUMN drivers.family_name IS 'Sobrenome do piloto';
COMMENT ON COLUMN drivers.nationality IS 'Gentílico principal do piloto';
COMMENT ON COLUMN drivers.date_of_birth IS 'Data de nascimento do piloto';

-- ============================================================================================================
-- 6. FATOS FÓRMULA 1 - CORRIDAS E RESULTADOS
-- ============================================================================================================

-- Corridas (tabela central do modelo F1)
CREATE TABLE races (
    id                  SERIAL PRIMARY KEY,
    race_ref            VARCHAR(255) NOT NULL UNIQUE, -- ID externo (de races.csv)
    season_id           INTEGER NOT NULL,            -- Temporada da corrida
    round               INTEGER NOT NULL,            -- Rodada do campeonato
    race_name           TEXT NOT NULL,               -- Nome da corrida
    race_date           DATE,                        -- Data da corrida
    race_time           TIME,                        -- Hora da corrida
    circuit_id          INTEGER NOT NULL,            -- Circuito da corrida
    CONSTRAINT fk_races_season
        FOREIGN KEY (season_id) REFERENCES seasons(id),
    CONSTRAINT fk_races_circuit
        FOREIGN KEY (circuit_id) REFERENCES circuits(id),
    CONSTRAINT uq_races_season_round
        UNIQUE (season_id, round) -- Uma corrida por temporada/rodada
);

COMMENT ON TABLE races IS 'Corridas da Fórmula 1 por temporada';
COMMENT ON COLUMN races.race_ref IS 'Identificador único vindo de races.csv';
COMMENT ON COLUMN races.round IS 'Rodada do campeonato (1, 2, 3, ..., 23)';
COMMENT ON COLUMN races.race_time IS 'Hora local de início da corrida';

-- Qualificações (tempos de qualifying)
CREATE TABLE qualifying (
    id                  SERIAL PRIMARY KEY,
    race_id             INTEGER NOT NULL,            -- Corrida da qualificação
    driver_id           INTEGER NOT NULL,            -- Piloto
    constructor_id      INTEGER NOT NULL,            -- Escuderia
    position            INTEGER,                     -- Posição na qualificação
    q1                  VARCHAR(16),                 -- Tempo Q1
    q2                  VARCHAR(16),                 -- Tempo Q2
    q3                  VARCHAR(16),                 -- Tempo Q3
    CONSTRAINT fk_qualifying_race
        FOREIGN KEY (race_id) REFERENCES races(id),
    CONSTRAINT fk_qualifying_driver
        FOREIGN KEY (driver_id) REFERENCES drivers(id),
    CONSTRAINT fk_qualifying_constructor
        FOREIGN KEY (constructor_id) REFERENCES constructors(id),
    CONSTRAINT uq_qualifying_race_driver
        UNIQUE (race_id, driver_id) -- Um resultado por piloto/corrida
);

COMMENT ON TABLE qualifying IS 'Resultados das sessões de qualificação';
COMMENT ON COLUMN qualifying.q1 IS 'Melhor tempo na fase Q1 (MM:SS.sss)';
COMMENT ON COLUMN qualifying.q2 IS 'Melhor tempo na fase Q2 (MM:SS.sss)';
COMMENT ON COLUMN qualifying.q3 IS 'Melhor tempo na fase Q3 (MM:SS.sss)';

-- Resultados das corridas
CREATE TABLE results (
    id                  SERIAL PRIMARY KEY,
    race_id             INTEGER NOT NULL,            -- Corrida
    driver_id           INTEGER NOT NULL,            -- Piloto
    constructor_id      INTEGER NOT NULL,            -- Escuderia
    grid                INTEGER,                     -- Posição no grid
    position            VARCHAR(5),                  -- Posição final (pode ter letras)
    position_order      INTEGER,                     -- Ordem de chegada
    points              NUMERIC(10,2),               -- Pontos ganhos
    laps                INTEGER,                     -- Voltas completadas
    status_id           INTEGER NOT NULL,            -- Status da corrida
    CONSTRAINT fk_results_race
        FOREIGN KEY (race_id) REFERENCES races(id),
    CONSTRAINT fk_results_driver
        FOREIGN KEY (driver_id) REFERENCES drivers(id),
    CONSTRAINT fk_results_constructor
        FOREIGN KEY (constructor_id) REFERENCES constructors(id),
    CONSTRAINT fk_results_status
        FOREIGN KEY (status_id) REFERENCES status(id),
    CONSTRAINT uq_results_race_driver
        UNIQUE (race_id, driver_id) -- Um resultado por piloto/corrida
);

COMMENT ON TABLE results IS 'Resultados detalhados de cada piloto em cada corrida';
COMMENT ON COLUMN results.position IS 'Posição final (1, 2, 3, ..., DNF, DNS, etc.)';
COMMENT ON COLUMN results.position_order IS 'Ordem de chegada (numérica)';
COMMENT ON COLUMN results.grid IS 'Posição de largada no grid';
COMMENT ON COLUMN results.status_id IS 'Referência ao status da corrida';

-- ============================================================================================================
-- 7. CLASSIFICAÇÕES (STANDINGS) - NORMALIZADAS
-- ============================================================================================================

-- Estratégia: Modelo normalizado para standings
-- - Tabela base `standings` contém dados comuns (posição, pontos, vitórias)
-- - Tabelas especializadas `driver_standings` e `constructor_standings` fazem o vínculo
-- - Permite extensibilidade e evita duplicação de colunas

-- Standings base (dados comuns a pilotos e construtores)
CREATE TABLE standings (
    id                  SERIAL PRIMARY KEY,
    season_id           INTEGER NOT NULL,            -- Temporada
    round               INTEGER NOT NULL,            -- Rodada do campeonato
    position            INTEGER,                     -- Posição na classificação
    points              NUMERIC(10,2),               -- Pontos acumulados
    wins                INTEGER,                     -- Número de vitórias
    CONSTRAINT fk_standings_season
        FOREIGN KEY (season_id) REFERENCES seasons(id)
);

COMMENT ON TABLE standings IS 'Classificações acumuladas por temporada e rodada';
COMMENT ON COLUMN standings.round IS 'Rodada do campeonato (0 = antes da primeira corrida)';
COMMENT ON COLUMN standings.position IS 'Posição na classificação do campeonato';
COMMENT ON COLUMN standings.wins IS 'Número de vitórias acumuladas na temporada';

-- Classificação de pilotos (especialização de standings)
CREATE TABLE driver_standings (
    standing_id         INTEGER NOT NULL,            -- Referência ao standing base
    driver_id           INTEGER NOT NULL,            -- Piloto classificado
    CONSTRAINT fk_driver_standings_standings
        FOREIGN KEY (standing_id) REFERENCES standings(id),
    CONSTRAINT fk_driver_standings_driver
        FOREIGN KEY (driver_id) REFERENCES drivers(id),
    CONSTRAINT pk_driver_standings
        PRIMARY KEY (standing_id, driver_id) -- Chave composta
);

COMMENT ON TABLE driver_standings IS 'Especialização da classificação para pilotos';
COMMENT ON COLUMN driver_standings.standing_id IS 'Referência aos dados de classificação';
COMMENT ON COLUMN driver_standings.driver_id IS 'Piloto nesta posição da classificação';

-- Classificação de construtores (especialização de standings)
CREATE TABLE constructor_standings (
    standing_id         INTEGER NOT NULL,            -- Referência ao standing base
    constructor_id      INTEGER NOT NULL,            -- Construtor classificado
    CONSTRAINT fk_constructor_standings_standings
        FOREIGN KEY (standing_id) REFERENCES standings(id),
    CONSTRAINT fk_constructor_standings_constructor
        FOREIGN KEY (constructor_id) REFERENCES constructors(id),
    CONSTRAINT pk_constructor_standings
        PRIMARY KEY (standing_id, constructor_id) -- Chave composta
);

COMMENT ON TABLE constructor_standings IS 'Especialização da classificação para construtores';
COMMENT ON COLUMN constructor_standings.standing_id IS 'Referência aos dados de classificação';
COMMENT ON COLUMN constructor_standings.constructor_id IS 'Construtor nesta posição da classificação';

-- Próximos passos:
-- 1. Executar o script de carga (carga.sql) para popular as tabelas