# SCC-541 – Laboratório de Bases de Dados
## Trabalho Prático T5 – Exercícios sobre Índices em PostgreSQL

> **Disciplina:** SCC-541 – Laboratório de Bases de Dados — ICMC/USP São Carlos  
> **Semestre:** 1º Semestre de 2026  
> **Entrega:** 27 de maio de 2026  

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

## 1. Introdução e Fundamentação Teórica

O objetivo deste documento é formalizar o projeto físico de banco de dados para o **Trabalho Prático T5**, descrevendo a estratégia de indexação adotada para otimizar o desempenho das consultas sobre a base de dados integrada de **Fórmula 1 + Cidades + Aeroportos**.

### 1.1. O que é um Índice em SGBDs?
Um índice é uma estrutura de dados auxiliar física que visa acelerar a recuperação de tuplas de uma tabela. Sem um índice adequado, o Sistema Gerenciador de Banco de Dados (SGBD) é forçado a percorrer sequencialmente todos os blocos de disco alocados para a tabela a fim de avaliar o predicado da consulta. Esse procedimento é conhecido como **`Sequential Scan` (Seq Scan)** e possui complexidade de tempo de pior caso linear $O(N)$ em relação ao número de tuplas.

Com a criação de um índice apropriado, o SGBD realiza uma busca direcionada na estrutura de índice (geralmente com complexidade logarítmica ou constante) para encontrar o endereço físico em disco da tupla correspondente, realizando um **`Index Scan`**.

### 1.2. Equilíbrio de Custos e Penalidades
Apesar de otimizarem drasticamente o tempo de leitura das consultas, os índices impõem penalidades ao sistema:
* **Espaço em Disco:** Cada índice requer armazenamento físico dedicado e estruturado.
* **Custo de Escrita:** Operações de modificação de dados (`INSERT`, `UPDATE`, `DELETE`) tornam-se mais onerosas, pois o SGBD precisa atualizar a tabela original e propagar as modificações de forma síncrona para todas as estruturas de índices associadas.

---

## 2. Estruturas Físicas de Índices Escolhidas

O PostgreSQL suporta variadas estruturas de acesso para índices. Em conformidade com o enunciado do trabalho, foram empregadas as estruturas **B-Tree** e **Hash**, alternando-as estrategicamente entre os exercícios práticos.

---

### 2.1. Exercício 1 — Busca de Piloto por Nome Exato e Nacionalidade

#### Predicado Analisado:
Busca por igualdade exata baseada na concatenação funcional de duas colunas textuais:
$$\text{driver\_name} = \text{given\_name} \mathbin{\Vert} \text{' '} \mathbin{\Vert} \text{family\_name}$$

#### Estrutura Adotada: **Índice Hash Funcional**
```sql
CREATE INDEX idx_drivers_fullname_hash ON drivers USING hash (((given_name || ' ' || family_name)));
```

#### Justificativa de Projeto:
1. **Natureza da Operação:** A consulta realiza um filtro de **igualdade estrita (`=`)** para localizar o registro de um único piloto ("Ayrton Senna"). A estrutura **Hash** é teoricamente ótima para pesquisas pontuais de igualdade, pois computa um valor de espalhamento (função hash) sobre a chave de busca e acessa diretamente o *bucket* correspondente em disco com complexidade de tempo média constante $\mathcal{O}(1)$.
2. **Índice Funcional:** Como o filtro é aplicado sobre o resultado de uma expressão de concatenação textual (`given_name || ' ' || family_name`), foi obrigatória a criação de um índice baseado em expressão. Isso evita que o PostgreSQL precise realizar a concatenação em tempo de execução para cada linha da tabela.
3. **Restrições da Estrutura Hash no PostgreSQL:** Índices do tipo Hash no PostgreSQL apresentam limitações severas de especificação. Eles **não suportam** a cláusula `INCLUDE` (índices de cobertura) e também não suportam cláusulas `WHERE` (índices parciais). Portanto, para retornar a coluna `nationality` exigida pelo enunciado, o otimizador necessariamente fará o mapeamento da chave no índice e depois acessará a tabela física em disco (*Heap*) para ler o atributo restante.

---

### 2.2. Exercício 2 — Cidades Brasileiras por Prefixo de Nome

#### Predicado Analisado:
Busca de intervalo textual através de correspondência de padrão de prefixo (`LIKE 'prefixo%'`), filtrando pelo identificador geográfico do país correspondente ao Brasil.

#### Estrutura Adotada: **Índice B-Tree Composto com Cobertura (INCLUDE)**
```sql
CREATE INDEX idx_cities_br_name_btree ON cities (country_id, name text_pattern_ops) 
INCLUDE (latitude, longitude, population);
```

#### Justificativa de Projeto:
1. **Natureza da Operação:** A consulta utiliza o operador `LIKE 'São%'`. Como os valores que atendem a este padrão residem dentro de um intervalo de ordenação alfabética (todas as strings que iniciam com a subcadeia "São"), a estrutura **B-Tree** é de uso obrigatório. O índice Hash é incapaz de atuar sobre filtros de intervalo ou prefixo devido ao espalhamento pseudo-aleatório das chaves.
2. **Operador de Classe `text_pattern_ops`:** Em bancos de dados que operam sob codificações UTF-8 e localidades específicas (diferentes do padrão binário `C`), o PostgreSQL falha ao tentar aplicar buscas com `LIKE` usando índices B-tree comuns. A especificação explícita do operador de classe `text_pattern_ops` faz com que o índice seja construído comparando os caracteres caractere por caractere (pelo valor binário cru), assegurando a utilização correta do índice B-tree para consultas com `LIKE 'padrão%'`.
3. **Índice de Cobertura (`INCLUDE`):** O enunciado solicita o retorno das colunas `latitude`, `longitude` e `population`. Para otimizar a performance ao patamar máximo, adicionamos estas colunas na cláusula `INCLUDE`. Desta forma, as folhas do índice B-tree armazenam, além das chaves de busca (`country_id` e `name`), os valores destes três atributos de retorno. Isso permite ao planejador de consultas executar um **`Index Only Scan`**, eliminando completamente o acesso a disco à tabela original física de cidades.

---

## 3. Exercício 3 — Resolução Teórica (LIKE com `%valor%`)

### Pergunta:
> *Estruturas B-trees conseguem indexar consultas com predicados do tipo `<Atributo> LIKE "%valor%"` ? (Considere que o atributo seja do tipo TEXT). Explique.*

### Resposta Formal:
**Não de forma eficiente.**

#### Explicação Física da Estrutura:
A árvore B-Tree ordena seus nós de forma sequencial de acordo com a ordenação das chaves indexadas (ordem lexicográfica para o tipo `TEXT`). A busca binária de alta performance ($\mathcal{O}(\log N)$) depende estritamente do conhecimento do caractere ou prefixo inicial da busca (ex.: `LIKE 'São%'`).

Ao utilizar um padrão com curinga no início (`LIKE '%valor%'`), o caractere de partida da string procurada torna-se **completamente desconhecido**. O termo buscado (ex.: "Silva") pode estar localizado no início ("Silva Senna"), no meio ("Ayrton Silva Senna") ou no fim ("Ayrton Senna Silva") de registros que alfabeticamente residem em posições totalmente dispersas e distantes dentro da árvore B-tree.

Dessa forma, o planejador de consultas perde a habilidade de realizar uma busca binária direcionada na árvore (Index Scan). Para responder à consulta utilizando uma B-Tree tradicional, o PostgreSQL seria obrigado a realizar uma varredura completa de todas as páginas de chaves do índice (**`Index Full Scan`**) ou, na maioria das vezes, abortar o índice e varrer sequencialmente a tabela inteira em disco (**`Seq Scan`**) aplicando a verificação de substring a cada tupla, o que gera um altíssimo custo de processamento e I/O.

#### Soluções Alternativas:
Para indexar de forma performática consultas com curinga inicial (`%valor%`), o PostgreSQL disponibiliza a extensão nativa **`pg_trgm`** (trigramas). Ela fatia os textos da tabela em substrings de três caracteres e constrói um índice **GIN (Generalized Inverted Index)**:

```sql
CREATE EXTENSION IF NOT EXISTS pg_trgm;
CREATE INDEX idx_cities_name_trgm ON cities USING GIN (name gin_trgm_ops);
```
O índice invertido GIN mapeia de forma altamente eficiente quais palavras contêm cada trigrama, permitindo um *Index Scan* rápido para qualquer busca por substring arbitrária.

---

## 4. Metodologia de Medição e Testes

A avaliação do desempenho prático de cada índice segue um rigoroso fluxo de testes estatísticos.

### 4.1. Loop de 100 Execuções
A medição do tempo de execução de uma consulta pontual pode sofrer distorções causadas por processos do sistema operacional concorrentes ou pelo estado de cache da memória física do servidor (carregamento inicial de blocos do HD para o Buffer Pool, gerando o efeito de *Cold Cache*).

Para mitigar ruídos e medir puramente a performance estrutural, o script implementa as funções **`Mede_Tempo_Q1`** e **`Mede_Tempo_Q2`**. Estas funções:
1. Capturam uma marca de tempo inicial em alta precisão (`CLOCK_TIMESTAMP`).
2. Executam a respectiva consulta **100 vezes** consecutivas, garantindo o aquecimento completo da memória RAM (*Warm Cache*).
3. Capturam a marca de tempo de término.
4. Calculam a média ponderada do tempo gasto por execução, fornecendo um indicativo estatístico robusto do desempenho da consulta em milissegundos (ms).

### 4.2. Roteiro Prático de Execução
Para reproduzir os resultados de performance do relatório do seu grupo:
1. Conecte-se à base de dados da disciplina via terminal ou interface visual (DBeaver / pgAdmin).
2. Execute o bloco de medição do Exercício correspondente **antes** de criar o índice e guarde o tempo médio informado pelo `Mede_Tempo`. Exiba o plano de execução com `EXPLAIN ANALYZE` (deve mostrar `Seq Scan`).
3. Execute o comando de criação do índice (`CREATE INDEX ...`).
4. Execute novamente o bloco de medição e registre o novo tempo médio (espera-se uma redução drástica). Exiba o novo plano com `EXPLAIN ANALYZE` (deve demonstrar `Index Scan` ou `Index Only Scan` usando a chave do índice criado).
