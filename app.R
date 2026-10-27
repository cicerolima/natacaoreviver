# Projeto Natação é Viver | Escolas do município de São Paulo
# Abra escolas_sp.Rproj, execute instalar_pacotes.R uma vez e clique em Run App.

pacotes <- c("shiny", "bslib", "leaflet", "sf", "readr", "dplyr", "DT", "htmltools", "htmlwidgets")
faltantes <- pacotes[!vapply(pacotes, requireNamespace, logical(1), quietly = TRUE)]
if (length(faltantes)) {
  stop(paste0("Pacotes ausentes: ", paste(faltantes, collapse = ", "),
              ". Execute source('instalar_pacotes.R') antes de abrir o aplicativo."), call. = FALSE)
}
library(shiny)
library(leaflet)
source(file.path("R", "natacao.R"), local = TRUE)
source(file.path("R", "dados.R"), local = TRUE)

limites <- ler_limites()
escolas <- ler_escolas(limites = limites)
geometrias <- limites_para_mapa(limites)
extensao_cidade <- sf::st_bbox(geometrias$zonas)
url_mapa <- Sys.getenv("ESCOLAS_TILE_URL", "https://tile.openstreetmap.org/{z}/{x}/{y}.png")
creditos_mapa <- Sys.getenv("ESCOLAS_TILE_ATTRIBUTION",
  '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors')
redes_disponiveis <- intersect(c("Municipal", "Estadual", "Federal", "Privada"), unique(escolas$rede))
portes_disponiveis <- c("Escola sem matrícula de escolarização",
  "Até 50 matrículas de escolarização", "Entre 51 e 200 matrículas de escolarização",
  "Entre 201 e 500 matrículas de escolarização", "Entre 501 e 1000 matrículas de escolarização",
  "Mais de 1000 matrículas de escolarização", "Não informado")
portes_disponiveis <- intersect(portes_disponiveis, unique(escolas$porte))
CORES_REDES <- c("Municipal" = "#31688E", "Estadual" = "#443A83",
                 "Federal" = "#9B781A", "Privada" = "#21918C")
CORES_PISCINA <- c("Sim" = "#176E73", "Não" = "#B4614E", "Não informado" = "#8A97A3")
fmt <- function(x) format(x, big.mark = ".", decimal.mark = ",", scientific = FALSE, trim = TRUE)
esc <- function(x) htmltools::htmlEscape(ifelse(is.na(x) | x == "", "Não informado", x))

popup_escola <- function(d) {
  paste0('<div class="escola-popup"><div class="popup-kicker">', esc(d$zona),
    ' · ', esc(d$rede), '</div><h3>', esc(d$escola), '</h3>',
    '<p class="popup-inep">INEP ', esc(d$id), '</p><p>', esc(d$endereco), '</p>',
    '<p><strong>Ensino:</strong> ', esc(d$etapas), '</p>',
    '<p><strong>Porte:</strong> ', esc(d$porte), '</p>',
    '<p><strong>Subprefeitura:</strong> ', esc(d$subprefeitura), '</p>',
    '<p><strong>Telefone:</strong> ', esc(d$telefone), '</p>',
    if ("piscina" %in% names(d)) paste0('<p><strong>Piscina:</strong> ', esc(d$piscina),
      '</p><p><strong>Estrutura de natação:</strong> ', esc(d$estrutura_natacao),
      '</p><p><strong>Alunos na natação (estimativa):</strong> ',
      ifelse(is.na(d$alunos_natacao), 'Não informado', fmt(d$alunos_natacao)), '</p>'), '</div>')
}

kpi <- function(rotulo, saida, detalhe, classe = "") {
  tags$div(class = paste("indicador", classe),
    tags$div(class = "indicador-rotulo", rotulo),
    tags$div(class = "indicador-valor", textOutput(saida, inline = TRUE)),
    tags$div(class = "indicador-detalhe", detalhe))
}
seletor <- function(id, label, choices, placeholder) {
  selectizeInput(id, label, choices = choices, selected = character(), multiple = TRUE,
    options = list(placeholder = placeholder, plugins = list("remove_button")))
}

ui <- fluidPage(
  title = "Escolas de São Paulo | Natação é Viver",
  theme = bslib::bs_theme(version = 5, bg = "#F3F5F7", fg = "#1B2B3A",
                         primary = "#176E73", base_font = "system-ui"),
  tags$head(
    tags$meta(name = "viewport", content = "width=device-width, initial-scale=1"),
    tags$link(rel = "stylesheet", type = "text/css", href = "estilo.css"),
    tags$script(src = "config.js", defer = NA),
    tags$script(src = "natacao.js", defer = NA)
  ),
  tags$header(class = "cabecalho",
    tags$div(class = "marca", tags$div(class = "marca-simbolo", "NV"),
      tags$div(tags$div(class = "marca-nome", "Natação é Viver"),
               tags$div(class = "marca-subtitulo", "Planejamento territorial"))),
    tags$div(class = "cabecalho-local", icon("location-dot"), " São Paulo · SP")
  ),
  tags$div(class = "estrutura",
    tags$button(type = "button", class = "alternar-filtros", `aria-controls` = "painel-filtros",
      `aria-expanded` = "false", icon("sliders"), " Filtros e visualização",
      onclick = "var p=document.getElementById('painel-filtros');var aberto=p.classList.toggle('filtros-abertos');this.setAttribute('aria-expanded',String(aberto));"),
    tags$aside(id = "painel-filtros", class = "filtros",
      tags$div(class = "filtros-topo", tags$h2("Explore a rede escolar"),
        tags$p("Combine os filtros para localizar escolas no território.")),
      textInput("busca", "Buscar escola, INEP ou endereço", placeholder = "Ex.: Vila Mariana"),
      selectInput("etapa", "Oferta de ensino", choices = c(ETAPA_PADRAO,
        "Ensino fundamental", "Ensino médio", "Fundamental e médio na mesma escola",
        "Todas as etapas"), selected = ETAPA_PADRAO),
      seletor("zonas", "Zona geográfica", c(ZONAS, "Sem localização", "Fora do município"), "Todas as zonas"),
      seletor("redes", "Dependência administrativa", redes_disponiveis, "Todas as redes"),
      seletor("subprefeituras", "Subprefeitura", sort(unique(limites$subprefeitura)), "Todas as subprefeituras"),
      seletor("portes", "Porte da escola", portes_disponiveis, "Todos os portes"),
      seletor("piscinas", "Tem piscina", names(CORES_PISCINA), "Todas as situações"),
      seletor("estruturas", "Estrutura de natação", c("Própria", "Terceirizada", "Não se aplica", "Não informado"), "Todas as estruturas"),
      checkboxInput("so_mapa", "Somente escolas localizadas no município", FALSE),
      actionButton("limpar", "Limpar filtros", icon = icon("rotate-left"), class = "btn-limpar"),
      tags$div(class = "filtro-legenda", "Campos vazios incluem todas as opções."),
      tags$hr(),
      tags$h3("Visualização do mapa"),
      selectInput("cor", "Colorir escolas por", choices = c("Zona geográfica" = "zona", "Rede de ensino" = "rede", "Piscina" = "piscina")),
      checkboxInput("agrupar", "Agrupar escolas próximas", TRUE),
      checkboxInput("mostrar_subpref", "Exibir limites das subprefeituras", FALSE),
      tags$div(class = "filtros-rodape", icon("circle-info"),
        " O Centro é mantido como região própria, conforme a divisão municipal.")
    ),
    tags$main(class = "conteudo",
      tags$div(class = "titulo-linha",
        tags$div(tags$div(class = "sobretitulo", "MAPEAMENTO ESCOLAR"),
          tags$h1("Escolas no território"),
          tags$p(class = "subtitulo", "Mapa da rede escolar do município de São Paulo")),
        downloadButton("baixar", "Exportar seleção", icon = icon("download"), class = "btn-exportar")
      ),
      tags$div(class = "indicadores",
        kpi("Escolas na seleção", "n_selecao", "Uma escola por código INEP"),
        kpi("Localizadas no mapa", "n_mapa", "Coordenadas dentro do município", "indicador-verde"),
        kpi("Sem ponto no mapa", "n_sem_ponto", "Ausências ou inconsistências", "indicador-atencao"),
        kpi("Cobertura da seleção", "cobertura", "Escolas localizadas / selecionadas")
      ),
      uiOutput("aviso"),
      tags$section(class = "painel painel-online", uiOutput("nv_conta")),
      tags$div(class = "mapa-layout",
        tags$section(class = "painel painel-mapa",
          tags$div(class = "painel-topo",
            tags$div(tags$h2("Distribuição das escolas"),
              tags$p("Clique nos pontos para abrir a ficha; nos grupos, para aproximar.")),
            actionButton("enquadrar", "Enquadrar seleção", icon = icon("expand"), class = "btn-mapa")),
          leafletOutput("mapa", height = "570px"),
          tags$div(class = "mapa-rodape", uiOutput("resumo_mapa", inline = TRUE),
            tags$span("Limites: Prefeitura de São Paulo / GeoSampa"))
        ),
        tags$div(class = "coluna-resumo",
          tags$section(class = "painel resumo-zonas",
            tags$div(class = "painel-topo", tags$div(tags$h2("Escolas por zona"),
              tags$p("Apenas as escolas localizadas da seleção."))),
            uiOutput("zonas_resumo")),
          tags$section(class = "painel ficha",
            tags$div(class = "painel-topo", tags$h2("Escola selecionada")),
            uiOutput("ficha"))
        )
      ),
      tags$section(class = "painel painel-tabela",
        tabsetPanel(id = "aba",
          tabPanel("Escolas", value = "escolas",
            tags$p(class = "tabela-instrucao", "Selecione uma linha para abrir a ficha e localizar a escola no mapa. Entre na conta para consultar e editar os campos de natação. A exportação usa os filtros laterais."),
            DT::DTOutput("tabela")),
          tabPanel("Qualidade dos dados", value = "qualidade",
            tags$div(class = "texto-metodo", uiOutput("qualidade_texto")),
            DT::DTOutput("tabela_qualidade")),
          tabPanel("Fontes e método", value = "metodo",
            tags$div(class = "texto-metodo",
              tags$h3("Base de escolas"),
              tags$p("Os campos de piscina, estrutura e alunos na natação são preenchidos pelos editores e ficam em uma base compartilhada, vinculada pelo código INEP. Não informado significa ausência de levantamento; zero alunos é um valor preenchido explicitamente. Os dados de natação são atualizados a cada 20 segundos enquanto a aba está visível e o usuário está conectado."),
              tags$p("Arquivo fornecido pelo usuário: Análise - Tabela da lista das escolas - Detalhado.csv. O arquivo não informa o ano de referência. Todas as linhas são preservadas; a abertura padrão seleciona escolas que oferecem ensino fundamental e/ou médio."),
              tags$h3("Localização e regiões"),
              tags$p("As colunas Latitude e Longitude são interpretadas como graus decimais em WGS84 (EPSG:4326). O arquivo não declara o datum; essa é a hipótese adotada para a visualização."),
              tags$p("A zona e a subprefeitura são obtidas por interseção do ponto com os polígonos completos da camada oficial geoportal:subprefeitura. O campo nm_regiao_05 fornece Norte, Leste, Sul, Oeste e Centro. A operação espacial usa UTM/SIRGAS2000 (EPSG:31983)."),
              tags$p("Pontos fora dos limites e coordenadas ausentes ou inválidas permanecem na tabela e não entram no mapa. Não há geocodificação pelo endereço nem correção automática das coordenadas. Em eventual limite compartilhado, usa-se o menor código de subprefeitura e a ambiguidade é sinalizada."),
              tags$p("Os contornos exibidos são simplificados com tolerância de 10 metros. A atribuição territorial utiliza os limites originais. A categoria de porte é uma faixa de matrículas, não uma contagem de alunos."),
              tags$p("Limites consultados em 16/10/2026. A cópia local acompanha o projeto; a atualização é opcional."),
              tags$p(tags$a(href = "https://geoinfo-smdu.github.io/tutorial-GeoSampa/", target = "_blank", rel = "noopener", "GeoSampa: documentação dos serviços e sistemas de referência")),
              tags$h3("Mapa de fundo"),
              tags$p("OpenStreetMap. O fundo exige internet. Os pontos, os polígonos e os filtros usam os arquivos locais do projeto."),
              tags$p("Os indicadores contam escolas, identificadas pelo código INEP. Uma escola que oferece as duas etapas é contada uma única vez. Os grupos do mapa reúnem pontos próximos; amplie para separar escolas no mesmo endereço."))
          )
        )
      ),
      tags$footer(class = "rodape", "Natação é Viver · São Paulo", tags$span("Painel exploratório de escolas"))
    )
  )
)

server <- function(input, output, session) {
  registros_natacao <- reactiveVal(natacao_vazia())
  estado_online <- reactiveVal(list(state = "loading", ready = FALSE, user = NULL))
  edicao <- reactiveVal(NULL)
  salvando <- reactiveVal(FALSE)
  pedido_salvar <- reactiveVal(NULL)
  escolas_com_natacao <- reactive(anexar_natacao(escolas, registros_natacao()))
  selecionada_id <- reactiveVal(NULL)
  selecionada <- reactive({
    id <- selecionada_id()
    if (is.null(id)) return(NULL)
    d <- escolas_com_natacao()
    i <- match(id, d$id)
    if (is.na(i)) return(NULL)
    d[i, , drop = FALSE]
  })
  observeEvent(input$nv_dados, {
    tryCatch(registros_natacao(ler_registros_natacao(input$nv_dados$rows)),
      error = function(e) showNotification("Não foi possível ler a base compartilhada. Atualize os dados antes de editar.", type = "error"))
  })
  observeEvent(input$nv_estado, {
    anterior <- estado_online()
    atual <- input$nv_estado
    estado_online(atual)
    if (identical(atual$state, "signed_in") && !identical(anterior$state, "signed_in")) removeModal()
    if (!identical(atual$state, "signed_in")) {
      registros_natacao(natacao_vazia())
      if (!is.null(edicao())) removeModal()
      edicao(NULL)
      salvando(FALSE)
    }
    if (length(atual$message) && nzchar(atual$message)) showNotification(atual$message, type = "warning", duration = 12)
  })
  output$nv_conta <- renderUI({
    e <- estado_online()
    conectado <- identical(e$state, "signed_in")
    texto <- switch(e$state,
      notconfigured = "Configure a conexão em www/config.js para ativar os dados compartilhados.",
      signed_in = if (isTRUE(e$ready)) paste0("Conectado como ", e$user$nome,
        " · Última consulta: ", horario_natacao(e$lastSync)) else "Consultando a base compartilhada…",
      loading = "Preparando conexão online…",
      "Entre para consultar e editar os dados compartilhados de natação.")
    tags$div(class = "online-linha",
      tags$div(tags$strong("Levantamento de natação"), tags$p(texto),
        if (conectado && isTRUE(e$ready)) tags$small("As alterações dos dois usuários são consultadas a cada 20 segundos.")),
      tags$div(class = "online-acoes", if (conectado) tagList(
        actionButton("nv_atualizar", "Atualizar dados", icon = icon("arrows-rotate")),
        actionButton("nv_sair", "Sair")) else
          actionButton("nv_abrir_login", "Entrar", icon = icon("right-to-bracket"))))
  })
  observeEvent(input$nv_abrir_login, {
    if (identical(estado_online()$state, "notconfigured")) {
      showNotification("Siga o arquivo LEIA_PRIMEIRO.md para conectar a base online.", type = "message")
      return()
    }
    showModal(modalDialog(title = "Acesso ao levantamento", footer = modalButton("Cancelar"),
      tags$form(class = "nv-login", onsubmit = "void window.NatacaoOnline.login(this); return false;",
        tags$label(`for` = "nv-email", "E-mail"),
        tags$input(id = "nv-email", name = "email", type = "email", required = NA,
          autocomplete = "username", class = "form-control"),
        tags$label(`for` = "nv-password", "Senha"),
        tags$input(id = "nv-password", name = "password", type = "password", required = NA,
          autocomplete = "current-password", class = "form-control"),
        tags$button(type = "submit", class = "btn btn-primary", "Entrar")),
      tags$p(class = "ajuda-natacao", "Use uma das duas contas autorizadas. Ao recarregar a página, entre novamente.")))
  })
  observeEvent(input$nv_atualizar, session$sendCustomMessage("nv_comando", list(action = "refresh")))
  observeEvent(input$nv_sair, {
    removeModal()
    edicao(NULL)
    session$sendCustomMessage("nv_comando", list(action = "logout"))
  })

  busca_lenta <- debounce(reactive(input$busca), 300)
  dados_filtrados <- reactive({
    d <- filtrar_escolas(escolas_com_natacao(), etapa = input$etapa, zonas = input$zonas,
      redes = input$redes, portes = input$portes, subprefeituras = input$subprefeituras,
      busca = busca_lenta(), so_mapa = input$so_mapa)
    if (length(input$piscinas)) d <- d[d$piscina %in% input$piscinas, , drop = FALSE]
    if (length(input$estruturas)) d <- d[d$estrutura_natacao %in% input$estruturas, , drop = FALSE]
    d
  })
  pontos <- reactive({
    d <- dados_filtrados()
    d[d$no_mapa, , drop = FALSE]
  })
  output$n_selecao <- renderText(fmt(nrow(dados_filtrados())))
  output$n_mapa <- renderText(fmt(nrow(pontos())))
  output$n_sem_ponto <- renderText(fmt(sum(!dados_filtrados()$no_mapa)))
  output$cobertura <- renderText({
    n <- nrow(dados_filtrados())
    if (!n) "—" else paste0(fmt(round(100 * nrow(pontos()) / n, 1)), "%")
  })
  output$aviso <- renderUI({
    d <- dados_filtrados()
    if (!nrow(d)) return(tags$div(class = "aviso aviso-vazio", icon("magnifying-glass"),
      " Nenhuma escola atende a esta combinação. Ajuste os filtros ou use Limpar filtros."))
    sem <- sum(!d$no_mapa)
    if (sem) tags$div(class = "aviso", icon("circle-info"), " ", fmt(sem),
      " escola(s) da seleção não aparecem no mapa. Consulte a aba Qualidade dos dados.")
  })
  output$resumo_mapa <- renderUI({
    tags$span(tags$strong(fmt(nrow(pontos()))), " de ", fmt(nrow(dados_filtrados())), " escolas da seleção no mapa")
  })

  output$mapa <- renderLeaflet({
    leaflet(options = leafletOptions(preferCanvas = TRUE, minZoom = 9, maxZoom = 19)) |>
      addTiles(urlTemplate = url_mapa, attribution = creditos_mapa, group = "OpenStreetMap") |>
      addMapPane("regioes", zIndex = 410) |>
      addMapPane("escolas", zIndex = 430) |>
      addPolygons(data = geometrias$zonas, group = "Zonas", layerId = ~paste0("zona::", zona),
        fillColor = ~unname(CORES_ZONAS[zona]), color = ~unname(CORES_ZONAS[zona]),
        weight = 2, opacity = 0.8, fillOpacity = 0.10, label = ~zona,
        highlightOptions = highlightOptions(weight = 3, fillOpacity = 0.21, bringToFront = FALSE),
        options = pathOptions(pane = "regioes")) |>
      addPolygons(data = geometrias$subprefeituras, group = "Subprefeituras", color = "#526172",
        weight = 1, opacity = 0.55, fill = FALSE, label = ~subprefeitura,
        options = pathOptions(pane = "regioes", interactive = FALSE)) |>
      hideGroup("Subprefeituras") |>
      addLayersControl(overlayGroups = "Zonas",
        options = layersControlOptions(collapsed = TRUE)) |>
      addScaleBar(position = "bottomleft", options = scaleBarOptions(imperial = FALSE)) |>
      fitBounds(lng1 = unname(extensao_cidade["xmin"]),
        lat1 = unname(extensao_cidade["ymin"]), lng2 = unname(extensao_cidade["xmax"]),
        lat2 = unname(extensao_cidade["ymax"]), options = list(padding = c(18, 18), maxZoom = 11))
  })

  observeEvent(input$mostrar_subpref, {
    proxy <- leafletProxy("mapa", session = session)
    if (isTRUE(input$mostrar_subpref)) showGroup(proxy, "Subprefeituras") else hideGroup(proxy, "Subprefeituras")
  })

  # Atualiza apenas pontos e legenda. O mapa não é reconstruído a cada filtro.
  observe({
    d <- pontos()
    paleta <- switch(input$cor, zona = CORES_ZONAS, rede = CORES_REDES, piscina = CORES_PISCINA)
    categorias <- d[[input$cor]]
    proxy <- leafletProxy("mapa", session = session) |>
      clearGroup("Escolas") |> clearMarkerClusters() |> clearPopups() |> removeControl("legenda")
    if (nrow(d)) {
      agrupamento <- if (isTRUE(input$agrupar)) markerClusterOptions(
        maxClusterRadius = 42, showCoverageOnHover = FALSE,
        spiderfyOnMaxZoom = TRUE,
        iconCreateFunction = htmlwidgets::JS("function(cluster) { return L.divIcon({html: '<span>' + cluster.getChildCount() + '</span>', className: 'grupo-escolas', iconSize: L.point(40,40)}); }")
      ) else NULL
      proxy <- addCircleMarkers(proxy, data = d, lng = ~longitude, lat = ~latitude,
        layerId = ~id, group = "Escolas", radius = 5, weight = 1.2, color = "#FFFFFF",
        fillColor = unname(paleta[categorias]), fillOpacity = 0.90,
        popup = popup_escola(d), label = ~escola,
        options = pathOptions(pane = "escolas"),
        clusterOptions = agrupamento, clusterId = "grupo_escolas")
    }
    addLegend(proxy, position = "bottomright", colors = unname(paleta), labels = names(paleta),
      title = switch(input$cor, zona = "Zona geográfica", rede = "Rede de ensino", piscina = "Piscina"), opacity = 1,
      layerId = "legenda")
  })

  enquadrar <- function(d) {
    proxy <- leafletProxy("mapa", session = session)
    if (!nrow(d)) return(invisible(NULL))
    if (nrow(d) == 1L || (diff(range(d$longitude)) < 1e-6 && diff(range(d$latitude)) < 1e-6)) {
      setView(proxy, lng = d$longitude[1], lat = d$latitude[1], zoom = 16)
    } else {
      fitBounds(proxy, lng1 = min(d$longitude), lat1 = min(d$latitude),
        lng2 = max(d$longitude), lat2 = max(d$latitude),
        options = list(padding = c(25, 25), maxZoom = 16))
    }
  }
  observeEvent(input$enquadrar, enquadrar(pontos()))
  # Filtros preservam a navegação; Enquadrar seleção aproxima quando o usuário desejar.
  observeEvent(input$mapa_shape_click, {
    id <- input$mapa_shape_click$id
    if (length(id) == 1L && startsWith(id, "zona::")) {
      updateSelectizeInput(session, "zonas", selected = substring(id, 7L))
    }
    # addCircleMarkers emite shape_click em versões do Leaflet.
    d <- pontos()
    i <- match(id, d$id)
    if (length(i) == 1L && !is.na(i)) selecionada_id(d$id[i])
  })
  observeEvent(input$mapa_marker_click, {
    d <- pontos()
    i <- match(input$mapa_marker_click$id, d$id)
    if (length(i) == 1L && !is.na(i)) selecionada_id(d$id[i])
  })

  output$zonas_resumo <- renderUI({
    d <- pontos()
    contagem <- table(factor(d$zona, levels = ZONAS))
    total <- nrow(d)
    maior <- max(1, contagem)
    tags$div(class = "barras-zonas", lapply(ZONAS, function(z) {
      n <- unname(contagem[z])
      tags$div(class = "zona-linha",
        tags$div(class = "zona-valores", tags$span(z), tags$strong(fmt(n))),
        tags$div(class = "barra-fundo", tags$div(class = "barra-zona",
          style = paste0("width:", 100 * n / maior, "%;background:", CORES_ZONAS[z], ";"))),
        tags$div(class = "zona-percentual", if (total) paste0(fmt(round(100 * n / total, 1)), "% das escolas no mapa") else "Sem escolas no mapa"))
    }))
  })

  output$ficha <- renderUI({
    d <- selecionada()
    if (is.null(d)) return(tags$div(class = "ficha-vazia", icon("school", class = "ficha-icone"),
      tags$p("Clique em uma escola no mapa ou selecione uma linha na tabela.")))
    tags$div(class = "ficha-conteudo",
      tags$div(class = "ficha-zona", d$zona_filtro, " · ", d$rede),
      tags$h3(d$escola), tags$p(class = "ficha-inep", "INEP ", d$id),
      tags$p(d$endereco), tags$p(tags$strong("Ensino: "), d$etapas),
      tags$p(tags$strong("Porte: "), d$porte), tags$p(tags$strong("Situação: "), d$situacao),
      if (identical(estado_online()$state, "signed_in") && isTRUE(estado_online()$ready)) tagList(
        tags$hr(), tags$p(tags$strong("Tem piscina: "), d$piscina),
        tags$p(tags$strong("Estrutura de natação: "), d$estrutura_natacao),
        tags$p(tags$strong("Alunos na natação (estimativa): "),
          if (is.na(d$alunos_natacao)) "Não informado" else fmt(d$alunos_natacao)),
        if (d$versao_natacao > 0) tags$p(class = "ajuda-natacao", "Atualizado por ",
          d$atualizado_por, " em ", horario_natacao(d$atualizado_em)),
        actionButton("editar_natacao", "Editar natação", icon = icon("pen"), class = "btn-editar-natacao")
      ) else tags$p(class = "ajuda-natacao", "Entre na conta para consultar e editar a natação."))
  })
  observeEvent(input$editar_natacao, {
    if (salvando()) {
      showNotification("Aguarde a confirmação da gravação em andamento.", type = "message")
      return()
    }
    req(identical(estado_online()$state, "signed_in"), isTRUE(estado_online()$ready))
    d <- selecionada()
    req(!is.null(d))
    edicao(list(inep = d$id, versao = d$versao_natacao))
    salvando(FALSE)
    showModal(modalDialog(title = paste0("Natação · ", d$escola), easyClose = FALSE,
      tags$p(class = "ajuda-natacao", "INEP ", d$id),
      radioButtons("ed_piscina", "A escola tem piscina?",
        choices = c("Não informado", "Sim", "Não"), selected = d$piscina, inline = TRUE),
      selectInput("ed_estrutura", "Piscina / estrutura para natação",
        choices = c("Não informado", "Própria", "Terceirizada", "Não se aplica"), selected = d$estrutura_natacao),
      numericInput("ed_alunos", "Número estimado de alunos que fazem natação",
        value = d$alunos_natacao, min = 0, max = .Machine$integer.max, step = 1),
      tags$p(class = "ajuda-natacao", "Deixe em branco se não houver estimativa. Zero significa nenhum aluno. Uma escola sem piscina pode utilizar estrutura terceirizada."),
      uiOutput("nv_edicao_status"),
      footer = tagList(modalButton("Cancelar"),
        actionButton("nv_salvar", "Salvar dados", icon = icon("floppy-disk"), class = "btn-primary"))))
  })
  output$nv_edicao_status <- renderUI({
    if (salvando()) tags$p(class = "ajuda-natacao", "Salvando na base compartilhada…")
  })
  observeEvent(input$nv_salvar, {
    req(!salvando(), !is.null(edicao()), identical(estado_online()$state, "signed_in"), isTRUE(estado_online()$ready))
    alunos <- tryCatch(list(ok = TRUE, valor = validar_alunos_natacao(input$ed_alunos)),
      error = function(e) list(ok = FALSE, mensagem = conditionMessage(e)))
    if (!alunos$ok) { showNotification(alunos$mensagem, type = "error"); return() }
    req(input$ed_piscina %in% c("Sim", "Não", "Não informado"),
        input$ed_estrutura %in% c("Própria", "Terceirizada", "Não se aplica", "Não informado"))
    pedido <- paste0(edicao()$inep, "-", input$nv_salvar)
    pedido_salvar(pedido)
    salvando(TRUE)
    session$sendCustomMessage("nv_comando", list(action = "save", requestId = pedido,
      inep = edicao()$inep, versao = edicao()$versao,
      tem_piscina = switch(input$ed_piscina, Sim = TRUE, "Não" = FALSE, NULL),
      estrutura = if (identical(input$ed_estrutura, "Não informado")) NULL else input$ed_estrutura,
      alunos_natacao = alunos$valor))
  })
  observeEvent(input$nv_resultado, {
    r <- input$nv_resultado
    req(identical(r$requestId, pedido_salvar()))
    salvando(FALSE)
    if (isTRUE(r$ok)) {
      removeModal()
      edicao(NULL)
      showNotification("Dados de natação salvos na base compartilhada.", type = "message")
    } else showNotification(r$message, type = "error", duration = NULL)
  })
  observeEvent(dados_filtrados(), {
    d <- selecionada()
    if (!is.null(d) && !d$id %in% dados_filtrados()$id) selecionada_id(NULL)
  }, ignoreInit = TRUE)

  output$tabela <- DT::renderDT({
    d <- exportar_colunas(dados_filtrados())
    d <- d[, c("Escola", "Código INEP", "Zona", "Rede", "Etapas de ensino", "Porte", "Tem piscina", "Estrutura de natação", "Alunos na natação (estimativa)", "Situação no mapa")]
    DT::datatable(d, rownames = FALSE, escape = TRUE, selection = "single",
      class = "compact stripe hover", options = list(
        pageLength = 10, lengthMenu = c(10, 25, 50, 100), scrollX = TRUE,
        searching = FALSE, order = list(list(0, "asc")), autoWidth = TRUE,
        language = list(lengthMenu = "Mostrar _MENU_ escolas", info = "_START_ a _END_ de _TOTAL_ escolas",
          infoEmpty = "Nenhuma escola", emptyTable = "Nenhuma escola encontrada com estes filtros",
          paginate = list(first = "Primeira", last = "Última", previous = "Anterior", "next" = "Próxima"))))
  }, server = TRUE)
  observeEvent(input$tabela_rows_selected, {
    i <- input$tabela_rows_selected
    d <- dados_filtrados()
    if (length(i) != 1L || i < 1L || i > nrow(d)) return()
    s <- d[i, , drop = FALSE]
    selecionada_id(s$id)
    if (isTRUE(s$no_mapa)) {
      leafletProxy("mapa", session = session) |>
        setView(lng = s$longitude, lat = s$latitude, zoom = 17) |>
        clearPopups() |>
        addPopups(lng = s$longitude, lat = s$latitude, popup = popup_escola(s),
                  options = popupOptions(maxWidth = 330))
    }
  })

  output$qualidade_texto <- renderUI({
    d <- dados_filtrados()
    tags$div(tags$p("Situação das ", tags$strong(fmt(nrow(d))), " escolas da seleção atual:"),
      tags$div(class = "qualidade-resumo", lapply(names(table(d$situacao)), function(s) {
        tags$span(class = "qualidade-item", tags$strong(fmt(sum(d$situacao == s))), " · ", s)
      })),
      tags$p("A tabela abaixo lista os registros sem ponto no mapa e eventuais pontos sobre limites. Escolas sem coordenadas não recebem uma zona por estimativa do endereço."))
  })
  output$tabela_qualidade <- DT::renderDT({
    d <- dados_filtrados()
    d <- d[!d$no_mapa | d$correspondencias_espaciais > 1L, , drop = FALSE]
    d <- exportar_colunas(d)[, c("Escola", "Código INEP", "Rede", "Endereço", "Latitude", "Longitude", "Situação no mapa")]
    DT::datatable(d, rownames = FALSE, escape = TRUE, selection = "none", class = "compact stripe",
      options = list(pageLength = 10, scrollX = TRUE, searching = FALSE,
        language = list(lengthMenu = "Mostrar _MENU_ registros", info = "_START_ a _END_ de _TOTAL_ registros",
          infoEmpty = "Nenhuma inconsistência nesta seleção", emptyTable = "Nenhuma inconsistência nesta seleção",
          paginate = list(previous = "Anterior", "next" = "Próxima"))))
  }, server = TRUE)

  output$baixar <- downloadHandler(
    filename = function() paste0("escolas_sp_selecao_", Sys.Date(), ".csv"),
    contentType = "text/csv; charset=UTF-8",
    content = function(file) readr::write_excel_csv2(exportar_colunas(dados_filtrados()), file, na = "")
  )
  observeEvent(input$limpar, {
    updateTextInput(session, "busca", value = "")
    updateSelectInput(session, "etapa", selected = ETAPA_PADRAO)
    for (id in c("zonas", "redes", "subprefeituras", "portes", "piscinas", "estruturas")) {
      updateSelectizeInput(session, id, selected = character())
    }
    updateCheckboxInput(session, "so_mapa", value = FALSE)
    selecionada_id(NULL)
    clearPopups(leafletProxy("mapa", session = session))
    DT::selectRows(DT::dataTableProxy("tabela", session = session), NULL)
  })
}

shinyApp(ui, server)
