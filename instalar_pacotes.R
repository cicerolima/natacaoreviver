# Execute uma vez no RStudio: source("instalar_pacotes.R")
pacotes <- c("shiny", "bslib", "leaflet", "sf", "readr", "dplyr", "DT", "htmltools", "htmlwidgets")
faltantes <- pacotes[!vapply(pacotes, requireNamespace, logical(1), quietly = TRUE)]
if (length(faltantes)) install.packages(faltantes, repos = "https://cloud.r-project.org")
message("Pacotes disponíveis. Abra app.R e clique em Run App ou execute shiny::runApp('.').")
