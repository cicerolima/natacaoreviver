# Opcional: atualiza a cópia local dos limites. Não é necessário para abrir o painel.
if (!requireNamespace("sf", quietly = TRUE)) stop("Instale o pacote sf primeiro.")
url <- paste0(
  "https://wfs.geosampa.prefeitura.sp.gov.br/geoserver/geoportal/wfs?",
  "service=WFS&version=2.0.0&request=GetFeature&",
  "typeNames=geoportal:subprefeitura&outputFormat=application%2Fjson&srsName=EPSG%3A4326"
)
temporario <- tempfile(fileext = ".geojson")
op <- options(timeout = max(180, getOption("timeout")))
tryCatch({
  utils::download.file(url, temporario, mode = "wb", quiet = FALSE)
  x <- sf::st_read(temporario, quiet = TRUE)
  stopifnot(nrow(x) == 32L,
            all(c("nm_subprefeitura", "nm_regiao_05", "cd_subprefeitura") %in% names(x)),
            setequal(unique(x$nm_regiao_05), c("Centro", "Leste", "Norte", "Oeste", "Sul")))
  dir.create("dados", showWarnings = FALSE)
  destino <- "dados/subprefeituras_geosampa_original.geojson"
  if (file.exists(destino)) file.copy(destino, paste0(destino, ".bak"), overwrite = TRUE)
  if (!file.copy(temporario, destino, overwrite = TRUE)) stop("Não foi possível gravar a camada.")
  message("Limites atualizados. Reinicie o aplicativo para reclassificar as escolas.")
}, finally = {
  options(op)
  unlink(temporario)
})
