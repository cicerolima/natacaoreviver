# Dados compartilhados: o navegador conversa com a API; o R recebe só dados e estado.
# Senhas e tokens de acesso não são enviados ao Shiny nem incluídos no repositório.
natacao_vazia <- function() {
  data.frame(inep = character(), tem_piscina = logical(), estrutura = character(),
    alunos_natacao = integer(), versao = integer(), atualizado_em = character(),
    atualizado_por = character(), stringsAsFactors = FALSE)
}

ler_registros_natacao <- function(registros) {
  if (!length(registros)) return(natacao_vazia())
  texto <- function(x) if (is.null(x) || !length(x)) NA_character_ else as.character(x)[1]
  numero <- function(x) if (is.null(x) || !length(x)) NA_real_ else as.numeric(x)[1]
  r <- do.call(rbind, lapply(registros, function(x) {
    data.frame(inep = texto(x$inep),
      tem_piscina = if (is.null(x$tem_piscina)) NA else isTRUE(x$tem_piscina),
      estrutura = texto(x$estrutura), alunos_natacao = numero(x$alunos_natacao),
      versao = numero(x$versao), atualizado_em = texto(x$atualizado_em),
      atualizado_por = texto(x$atualizado_por), stringsAsFactors = FALSE)
  }))
  if (anyNA(r$inep) || anyDuplicated(r$inep)) stop("Resposta de natação com INEP inválido ou repetido.")
  r
}

anexar_natacao <- function(d, registros = natacao_vazia()) {
  i <- match(d$id, registros$inep)
  d$tem_piscina <- registros$tem_piscina[i]
  d$piscina <- ifelse(is.na(d$tem_piscina), "Não informado",
                      ifelse(d$tem_piscina, "Sim", "Não"))
  d$estrutura_natacao <- registros$estrutura[i]
  d$estrutura_natacao[is.na(d$estrutura_natacao)] <- "Não informado"
  d$alunos_natacao <- registros$alunos_natacao[i]
  d$versao_natacao <- registros$versao[i]
  d$versao_natacao[is.na(d$versao_natacao)] <- 0
  d$atualizado_em <- registros$atualizado_em[i]
  d$atualizado_por <- registros$atualizado_por[i]
  d
}

horario_natacao <- function(x) {
  if (!length(x) || is.na(x) || !nzchar(x)) return("—")
  t <- as.POSIXct(x, format = "%Y-%m-%dT%H:%M:%OS", tz = "UTC")
  if (is.na(t)) return(x)
  format(t, "%d/%m/%Y %H:%M", tz = "America/Sao_Paulo")
}

validar_alunos_natacao <- function(x) {
  if (is.null(x) || !length(x) || is.na(x)) return(NULL)
  if (!is.numeric(x) || length(x) != 1L || !is.finite(x) ||
      x < 0 || x != floor(x) || x > .Machine$integer.max) {
    stop("Informe um número inteiro de alunos, maior ou igual a zero, ou deixe em branco.", call. = FALSE)
  }
  as.integer(x)
}
