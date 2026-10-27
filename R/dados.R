# Leitura, classificação espacial e filtros compartilhados pelo aplicativo.
# Coordenadas da planilha: graus decimais, interpretados como WGS84 (EPSG:4326).

ZONAS <- c("Zona Norte", "Zona Leste", "Zona Sul", "Zona Oeste", "Centro")
CORES_ZONAS <- c(
  "Zona Norte" = "#443A83", "Zona Leste" = "#21918C",
  "Zona Sul" = "#58A96B", "Zona Oeste" = "#31688E", "Centro" = "#B99B23"
)
ETAPA_PADRAO <- "Fundamental e/ou médio"

texto_busca <- function(x) {
  x[is.na(x)] <- ""
  # A transliteração do iconv varia no webR. Trate os acentos latinos usados
  # nos nomes brasileiros explicitamente, preservando a busca no Shinylive.
  x <- chartr("ÁÀÂÃÄáàâãäÉÈÊËéèêëÍÌÎÏíìîïÓÒÔÕÖóòôõöÚÙÛÜúùûüÇçÑñ",
              "AAAAAaaaaaEEEEeeeeIIIIiiiiOOOOOoooooUUUUuuuuCcNn", enc2utf8(x))
  tolower(iconv(x, from = "UTF-8", to = "ASCII//TRANSLIT", sub = ""))
}

numero_coordenada <- function(x) {
  suppressWarnings(as.numeric(gsub(",", ".", trimws(x), fixed = TRUE)))
}

ler_limites <- function(pasta = "dados") {
  arquivo <- file.path(pasta, "subprefeituras_geosampa_original.geojson")
  if (!file.exists(arquivo)) {
    stop("Limites ausentes. Execute source('scripts/atualizar_limites.R').", call. = FALSE)
  }
  x <- sf::st_read(arquivo, quiet = TRUE)
  campos <- c("cd_subprefeitura", "nm_subprefeitura", "nm_regiao_05")
  if (!all(campos %in% names(x))) stop("A camada do GeoSampa mudou de estrutura.")
  x <- sf::st_make_valid(x)
  x <- x[order(x$cd_subprefeitura), ]
  x$subprefeitura <- x$nm_subprefeitura
  x$zona <- ifelse(x$nm_regiao_05 == "Centro", "Centro",
                   paste("Zona", x$nm_regiao_05))
  if (!setequal(unique(x$zona), ZONAS)) stop("Regiões inesperadas na camada municipal.")
  sf::st_transform(x, 4326)
}

ler_escolas <- function(arquivo = "dados/escolas_original.csv", limites = ler_limites()) {
  if (!file.exists(arquivo)) stop("Não foi encontrado o arquivo dados/escolas_original.csv.")
  bruto <- readr::read_csv(
    arquivo, col_types = readr::cols(.default = readr::col_character()),
    locale = readr::locale(encoding = "UTF-8"), show_col_types = FALSE,
    progress = FALSE, name_repair = "minimal"
  )
  campos <- c("Escola", "Código INEP", "Município", "Latitude", "Longitude",
              "Dependência Administrativa", "Categoria Administrativa", "Endereço",
              "Telefone", "Porte da Escola", "Etapas e Modalidade de Ensino Oferecidas")
  faltam <- setdiff(campos, names(bruto))
  if (length(faltam)) stop(paste("Colunas ausentes:", paste(faltam, collapse = ", ")))
  if (anyDuplicated(bruto[["Código INEP"]])) {
    stop("Há códigos INEP repetidos. Revise as duplicidades antes de carregar a base.")
  }
  d <- dplyr::transmute(
    bruto, id = `Código INEP`, escola = Escola, municipio = Município,
    rede = `Dependência Administrativa`, categoria = `Categoria Administrativa`,
    endereco = Endereço, telefone = Telefone,
    porte = dplyr::coalesce(`Porte da Escola`, "Não informado"),
    etapas = dplyr::coalesce(`Etapas e Modalidade de Ensino Oferecidas`, "Não informado"),
    latitude_original = Latitude, longitude_original = Longitude,
    latitude = numero_coordenada(Latitude), longitude = numero_coordenada(Longitude)
  )
  if (any(texto_busca(d$municipio) != "sao paulo")) {
    stop("A base contém municípios diferentes de São Paulo. Revise a seleção municipal.")
  }
  d$fundamental <- grepl("Ensino Fundamental", d$etapas, fixed = TRUE)
  d$medio <- grepl("Ensino Médio", d$etapas, fixed = TRUE)
  ausente <- is.na(d$latitude_original) | is.na(d$longitude_original) |
    !nzchar(trimws(d$latitude_original)) | !nzchar(trimws(d$longitude_original))
  valida <- !ausente & is.finite(d$latitude) & is.finite(d$longitude) &
    abs(d$latitude) <= 90 & abs(d$longitude) <= 180
  d$zona <- NA_character_
  d$subprefeitura <- NA_character_
  d$situacao <- ifelse(ausente, "Sem coordenadas", "Coordenadas inválidas")
  d$correspondencias_espaciais <- 0L
  linhas <- which(valida)
  if (length(linhas)) {
    pontos <- sf::st_as_sf(d[linhas, ], coords = c("longitude", "latitude"), crs = 4326)
    # Predicado em UTM/SIRGAS2000, com os limites completos, sem simplificação.
    hits <- sf::st_intersects(sf::st_transform(pontos, 31983),
                              sf::st_transform(limites, 31983))
    d$correspondencias_espaciais[linhas] <- lengths(hits)
    indice <- vapply(hits, function(h) if (length(h)) h[1] else NA_integer_, integer(1))
    d$zona[linhas] <- limites$zona[indice]
    d$subprefeitura[linhas] <- limites$subprefeitura[indice]
    d$situacao[linhas] <- ifelse(lengths(hits) == 0L, "Fora do município",
                                ifelse(lengths(hits) > 1L,
                                       "No mapa (limite administrativo)", "No mapa"))
  }
  # Em um limite compartilhado, usa o menor código de subprefeitura e registra a ambiguidade.
  d$no_mapa <- !is.na(d$zona)
  d$zona_filtro <- ifelse(d$no_mapa, d$zona,
                          ifelse(d$situacao == "Fora do município", "Fora do município",
                                 "Sem localização"))
  d$busca <- texto_busca(paste(d$escola, d$id, d$endereco))
  d
}

limites_para_mapa <- function(limites) {
  sub_utm <- sf::st_transform(limites[, c("subprefeitura", "zona")], 31983)
  zonas_utm <- dplyr::summarise(dplyr::group_by(sub_utm, zona), .groups = "drop")
  # Somente a geometria exibida é simplificada (10 m); a classificação usa o original.
  list(
    subprefeituras = sf::st_transform(sf::st_simplify(sub_utm, dTolerance = 10,
                                                     preserveTopology = TRUE), 4326),
    zonas = sf::st_transform(sf::st_simplify(zonas_utm, dTolerance = 10,
                                             preserveTopology = TRUE), 4326)
  )
}

filtrar_escolas <- function(d, etapa = ETAPA_PADRAO, zonas = character(),
                           redes = character(), portes = character(),
                           subprefeituras = character(), busca = "", so_mapa = FALSE) {
  manter <- switch(etapa,
    "Fundamental e/ou médio" = d$fundamental | d$medio,
    "Ensino fundamental" = d$fundamental,
    "Ensino médio" = d$medio,
    "Fundamental e médio na mesma escola" = d$fundamental & d$medio,
    "Todas as etapas" = rep(TRUE, nrow(d)),
    stop("Etapa de ensino desconhecida.")
  )
  if (length(zonas)) manter <- manter & d$zona_filtro %in% zonas
  if (length(redes)) manter <- manter & d$rede %in% redes
  if (length(portes)) manter <- manter & d$porte %in% portes
  if (length(subprefeituras)) manter <- manter & d$subprefeitura %in% subprefeituras
  if (isTRUE(so_mapa)) manter <- manter & d$no_mapa
  if (length(busca) && nzchar(trimws(busca))) {
    termos <- strsplit(texto_busca(trimws(busca)), "[[:space:]]+")[[1]]
    for (termo in termos) manter <- manter & grepl(termo, d$busca, fixed = TRUE)
  }
  d[which(manter), , drop = FALSE]
}

exportar_colunas <- function(d) {
  if (!"piscina" %in% names(d)) d <- anexar_natacao(d)
  dplyr::transmute(d, Escola = escola, `Código INEP` = id,
    Zona = zona_filtro, Subprefeitura = subprefeitura, Rede = rede,
    `Categoria administrativa` = categoria, `Etapas de ensino` = etapas,
    Porte = porte, Endereço = endereco, Telefone = telefone,
    Latitude = latitude, Longitude = longitude, `Situação no mapa` = situacao,
    `Tem piscina` = piscina, `Estrutura de natação` = estrutura_natacao,
    `Alunos na natação (estimativa)` = alunos_natacao,
    `Atualizado por` = atualizado_por, `Atualizado em (UTC)` = atualizado_em)
}
