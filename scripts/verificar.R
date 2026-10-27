# Verificação reproduzível: Rscript scripts/verificar.R, a partir da pasta do projeto.
source("R/natacao.R")
source("R/dados.R")
l <- ler_limites()
d <- ler_escolas(limites = l)
s <- filtrar_escolas(d)
bruto <- readr::read_csv("dados/escolas_original.csv", show_col_types = FALSE,
                         col_types = readr::cols(.default = readr::col_character()))

# Contagem independente do recorte, a partir das colunas originais.
etapas_brutas <- bruto[["Etapas e Modalidade de Ensino Oferecidas"]]
etapas_brutas[is.na(etapas_brutas)] <- ""
esperado <- grepl("Ensino Fundamental", etapas_brutas, fixed = TRUE) |
  grepl("Ensino Médio", etapas_brutas, fixed = TRUE)
stopifnot(nrow(d) == nrow(bruto), nrow(s) == sum(esperado), !anyDuplicated(s$id),
          nrow(l) == 32L, setequal(unique(l$zona), ZONAS),
          all(sf::st_is_valid(l)),
          all(s$no_mapa == !is.na(s$subprefeitura)))

# Âncoras espaciais identificadas na base original, em regiões diferentes.
stopifnot(d$zona[d$id == "35000012"] == "Zona Oeste",
          d$zona[d$id == "35000024"] == "Zona Norte")

# Interseções de filtros, escolas que oferecem ambas as etapas e nenhum resultado.
f <- filtrar_escolas(d, etapa = "Ensino fundamental")
m <- filtrar_escolas(d, etapa = "Ensino médio")
fm <- filtrar_escolas(d, etapa = "Fundamental e médio na mesma escola")
stopifnot(nrow(s) == nrow(f) + nrow(m) - nrow(fm),
          nrow(filtrar_escolas(d, etapa = "Todas as etapas")) == nrow(d),
          all(filtrar_escolas(d, zonas = "Zona Sul", redes = "Municipal")$zona == "Zona Sul"),
          all(filtrar_escolas(d, zonas = "Zona Sul", redes = "Municipal")$rede == "Municipal"),
          nrow(filtrar_escolas(d, busca = "ESCOLA_INEXISTENTE_XYZ_987")) == 0L,
          nrow(filtrar_escolas(d, busca = "35000012")) == 1L,
          nrow(filtrar_escolas(d, busca = "[.*")) == 0L,
          identical(texto_busca("São Luís"), "sao luis"),
          all(filtrar_escolas(d, so_mapa = TRUE)$no_mapa))

# Casos de coordenada: ausente, inválida e fora da cidade não podem ganhar uma zona.
fixture <- bruto[1:4, ]
fixture$Latitude <- c("", "abc", "-22.90", "-23,51227")
fixture$Longitude <- c("-46.75", "-46.75", "-43.20", "-46,74971")
arq <- tempfile(fileext = ".csv")
readr::write_csv(fixture, arq, na = "")
q <- ler_escolas(arq, l)
unlink(arq)
stopifnot(identical(q$situacao[1:3], c("Sem coordenadas", "Coordenadas inválidas", "Fora do município")),
          !any(q$no_mapa[1:3]), all(is.na(q$zona[1:3])), q$no_mapa[4],
          q$zona[4] == "Zona Oeste")

# Geometrias exibidas e exportação UTF-8 com identificadores preservados.
mapas <- limites_para_mapa(l)
stopifnot(nrow(mapas$zonas) == 5L, all(sf::st_is_valid(mapas$zonas)))
arq <- tempfile(fileext = ".csv")
readr::write_excel_csv2(exportar_colunas(s), arq, na = "")
volta <- readr::read_csv2(arq, col_types = readr::cols(.default = readr::col_character()),
                          show_col_types = FALSE)
unlink(arq)
stopifnot(nrow(volta) == nrow(s), identical(volta[["Código INEP"]], s$id))

dir.create("verificacao", showWarnings = FALSE)
relatorio <- c(
  "VERIFICAÇÃO DO DASHBOARD DE ESCOLAS — SÃO PAULO",
  paste("Execução:", format(Sys.time(), tz = "America/Sao_Paulo", usetz = TRUE)),
  paste("R:", getRversion()),
  paste("Registros originais:", nrow(d)),
  paste("Escolas com fundamental e/ou médio:", nrow(s)),
  paste("Escolas do recorte localizadas no município:", sum(s$no_mapa)),
  paste("Escolas do recorte sem ponto no mapa:", sum(!s$no_mapa)),
  "",
  capture.output(print(table(s$zona_filtro))),
  "",
  "Aprovado: contagens, INEP único, recorte sem dupla contagem, filtros combinados,",
  "busca literal e sem acentos, casos sem resultado, ausência e invalidez de coordenadas,",
  "pontos externos, interseção com limites completos, geometrias válidas e exportação CSV.",
  "",
  vapply(c("shiny", "bslib", "leaflet", "sf", "readr", "dplyr", "DT"),
    function(p) if (requireNamespace(p, quietly = TRUE)) paste(p, as.character(utils::packageVersion(p))) else paste(p, "não instalado"), character(1))
)
writeLines(relatorio, "verificacao/relatorio.txt", useBytes = TRUE)
cat(paste(relatorio, collapse = "\n"), "\n")
