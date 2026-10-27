# Escolas de São Paulo — R Shiny

Dashboard do Projeto Natação é Viver para explorar a localização das escolas do município de São Paulo.

**Atualização de 27/10/2026:** cadastro compartilhado de piscina, estrutura própria/terceirizada e alunos estimados na natação. Consulte **LEIA_PRIMEIRO.md** para conectar o Supabase e autorizar as duas contas. O pacote inclui o código de integração; a conexão precisa ser configurada no seu projeto Supabase antes do uso online.

## Como abrir no RStudio

1. Extraia **todo o ZIP** para uma pasta no computador.
2. Abra `escolas_sp.Rproj`. O projeto define a pasta de trabalho correta.
3. No console do RStudio, execute uma vez:

```r
source("instalar_pacotes.R")
```

4. Abra `app.R` e clique em **Run App**, ou execute:

```r
shiny::runApp(".", launch.browser = TRUE)
```

É necessário R 4.1 ou superior; recomenda-se uma instalação atual de R e RStudio. No Windows, use os pacotes binários oferecidos pelo CRAN. Em Linux, o pacote `sf` também requer as bibliotecas de sistema GDAL, GEOS, PROJ e UDUNITS2.

Os dados e limites já acompanham o projeto. O aplicativo não precisa baixar a malha municipal ao iniciar. A instalação dos pacotes e o carregamento do mapa de fundo exigem internet.

## O que o painel oferece

- Mapa interativo OpenStreetMap, com zoom, agrupamento de pontos e ficha da escola.
- Contornos das zonas Norte, Leste, Sul e Oeste, além do Centro, conforme o campo de região da Prefeitura.
- Filtros combinados por ensino, zona, dependência administrativa, subprefeitura e porte.
- Busca por nome, código INEP ou endereço, sem diferenciar acentos e maiúsculas.
- Contadores da seleção, escolas no mapa, registros sem ponto e cobertura de localização.
- Distribuição das escolas localizadas por zona e tabela com seleção de linhas.
- Exportação da seleção em CSV com separador `;`, vírgula decimal e UTF-8 com BOM, adequado ao Excel em português.
- Aba de qualidade com os registros que não podem ser representados no mapa.

Ao selecionar uma zona no próprio mapa, o filtro geográfico é atualizado. Ao selecionar uma escola na tabela, o mapa aproxima sua localização. O botão **Enquadrar seleção** ajusta o mapa aos resultados; os demais filtros preservam o enquadramento escolhido. Escolas em um mesmo endereço podem se sobrepor: os grupos se abrem ao ampliar até o nível máximo.

Um seletor múltiplo vazio inclui todas as opções. **Limpar filtros** restaura o recorte padrão de fundamental e/ou médio. **Todas as etapas** permite consultar também as demais escolas do arquivo.

## O que foi encontrado na base

| Informação | Escolas |
| --- | ---: |
| Total do arquivo | 7.856 |
| Oferecem ensino fundamental e/ou médio | 3.155 |
| Desse recorte, localizadas dentro do município | 2.968 |
| Desse recorte, sem coordenadas | 187 |

O arquivo inclui educação infantil e outras modalidades. Por isso o painel aplica o recorte de fundamental e/ou médio por padrão, sem remover linhas da base original. Uma escola que oferece ambas as etapas conta uma única vez. O arquivo não informa ano de referência e as faixas de porte não equivalem a uma contagem exata de alunos.

| Zona | Escolas do recorte com localização |
| --- | ---: |
| Norte | 614 |
| Leste | 1.050 |
| Sul | 933 |
| Oeste | 278 |
| Centro | 93 |
| Total | 2.968 |

Escolas sem coordenadas não recebem uma zona por inferência de endereço. A distribuição por zona e seus percentuais usam apenas escolas localizadas.

## Fontes e classificação espacial

**Escolas:** arquivo fornecido pelo usuário, `Análise - Tabela da lista das escolas - Detalhado.csv`, preservado integralmente como `dados/escolas_original.csv`.

**Limites:** Prefeitura de São Paulo / GeoSampa, camada WFS `geoportal:subprefeitura`, consultada em 16/10/2026. São 32 polígonos com o campo oficial `nm_regiao_05`, que identifica as cinco regiões.

- Documentação municipal: https://geoinfo-smdu.github.io/tutorial-GeoSampa/
- Serviço WFS: https://wfs.geosampa.prefeitura.sp.gov.br/geoserver/geoportal/wfs
- Consulta usada: `service=WFS&version=2.0.0&request=GetFeature&typeNames=geoportal:subprefeitura&outputFormat=application%2Fjson&srsName=EPSG%3A4326`
- Mapa de fundo: OpenStreetMap, com créditos exibidos no mapa.

As coordenadas da escola são interpretadas como graus decimais em **WGS84/EPSG:4326**, pois o CSV não declara o datum. A classificação de zona/subprefeitura resulta da interseção do ponto com os limites completos, em **UTM/SIRGAS2000/EPSG:31983**. A geometria exibida é simplificada em 10 metros para agilizar a navegação; essa simplificação não é usada para classificar os pontos.

Não se faz geocodificação pelo endereço, deslocamento para o polígono mais próximo ou correção automática de latitude/longitude. Pontos externos, inválidos ou ausentes ficam sinalizados na tabela. Se um ponto coincidir com um limite compartilhado, o menor código de subprefeitura decide a atribuição e a situação registra a ambiguidade.

No celular, use **Filtros e visualização** para abrir ou recolher os controles. Para usar outro provedor de mapa no futuro, configure as variáveis de ambiente `ESCOLAS_TILE_URL` e `ESCOLAS_TILE_ATTRIBUTION` antes de iniciar o Shiny.

## Arquivos do projeto

| Arquivo | Função |
| --- | --- |
| `app.R` | Interface e reatividade do Shiny |
| `R/dados.R` | Leitura, classificação espacial, filtros e exportação |
| `R/natacao.R` | Associação do levantamento pelo INEP e validação de alunos |
| `www/config.js` | URL e chave publicável do projeto Supabase |
| `www/natacao.js` | Login, leitura, gravação e atualização compartilhada |
| `supabase/01_estrutura.sql` | Tabelas, permissões e gravação com controle de conflitos |
| `supabase/02_autorizar_editores.sql` | Lista de contas autorizadas |
| `www/estilo.css` | Estilo e adaptação de tela |
| `instalar_pacotes.R` | Instalação dos pacotes ausentes |
| `dados/escolas_original.csv` | Cópia integral do arquivo recebido |
| `dados/escolas_classificadas.csv` | Classificação de todas as escolas na data da entrega |
| `dados/subprefeituras_geosampa_original.geojson` | Limites municipais completos |
| `dados/zonas_sp_mapa.geojson` | Contornos de zona derivados da camada municipal |
| `scripts/atualizar_limites.R` | Atualização opcional da malha oficial |
| `scripts/verificar.R` | Verificação reproduzível de dados, filtros e geometrias |
| `verificacao/relatorio.txt` | Resultado das verificações executadas |

O aplicativo recalcula as classificações a partir dos originais ao iniciar. O CSV classificado e o GeoJSON de zonas são cópias de apoio e não alimentam os indicadores do painel.

## Atualizar a base

Substitua `dados/escolas_original.csv` por um CSV com os mesmos cabeçalhos e formato do original, separado por vírgulas e codificado em UTF-8. Reinicie o aplicativo. O mapa e os filtros serão recalculados. Códigos INEP duplicados ou colunas obrigatórias ausentes interrompem a leitura com uma mensagem específica.

Para atualizar os limites, execute `source("scripts/atualizar_limites.R")` na pasta do projeto e reinicie o painel. O script conserva uma cópia `.bak` antes de substituir a camada local. Para verificar uma nova base, execute `source("scripts/verificar.R")`. As tabelas numéricas deste README descrevem a entrega inicial.
