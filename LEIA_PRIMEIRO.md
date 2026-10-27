# Atualização: levantamento compartilhado de natação

O mapa e os filtros da versão anterior foram mantidos. Selecione uma escola no mapa ou na tabela e use **Editar natação**, após entrar na conta.

| Campo | Valores |
| --- | --- |
| A escola tem piscina? | Sim, Não ou Não informado |
| Piscina / estrutura para natação | Própria, Terceirizada, Não se aplica ou Não informado |
| Alunos que fazem natação | Número inteiro estimado, zero ou campo em branco |

**Não informado e zero são diferentes.** O aplicativo não estima alunos a partir do porte da escola e não transforma ausência de piscina em zero alunos. Uma escola pode utilizar estrutura terceirizada. Os três campos são independentes, para registrar esses casos.

Cada registro usa o **código INEP**. As alterações ficam no Supabase e aparecem para os dois usuários em até 20 segundos enquanto a aba estiver visível; **Atualizar dados** consulta imediatamente. O nome do último editor e a data ficam na ficha e no CSV exportado. Se as duas pessoas editarem a mesma escola, a segunda gravação avisa o conflito e preserva os valores já salvos. Para continuar, feche a edição, consulte a versão atual e abra o formulário novamente.

## Conectar uma vez

1. Crie um projeto no [Supabase](https://supabase.com/). No **SQL Editor**, execute `supabase/01_estrutura.sql`.
2. Em **Authentication > Users**, crie as duas contas com seus respectivos e-mails e senhas. Use a opção de confirmar as contas ao criá-las. Cada pessoa deve usar sua própria conta. A troca de senha pode ser feita pelas ferramentas de administração do Supabase.
3. Edite os dois e-mails e os nomes em `supabase/02_autorizar_editores.sql`. Execute esse arquivo no **SQL Editor** e confira se o resultado mostra as duas contas. Somente usuários dessa lista conseguem ler e salvar o levantamento.
4. Em `www/config.js`, preencha a URL do projeto e sua **publishable key**, disponíveis nas configurações de API do Supabase:

```javascript
window.NV_CONFIG = {
  supabaseUrl: "https://SEU_PROJETO.supabase.co",
  supabasePublishableKey: "sb_publishable_SUA_CHAVE_PUBLICA"
};
```

A chave publicável é feita para uso no navegador. As permissões são controladas no banco pelo login e pela lista de editores. Não coloque senha, `sb_secret_...` ou `service_role` no projeto. A antiga chave `anon` também é aceita.

5. Substitua o projeto anterior por **todo o conteúdo deste pacote**, preservando a estrutura de pastas. Não basta trocar apenas o `app.R`: há novos arquivos em `R/`, `www/` e `supabase/`. Publique pelo fluxo que você já utiliza. Os arquivos `supabase/*.sql` são para a configuração no painel; não são executados automaticamente pelo aplicativo.

## GitHub Pages

Se o aplicativo roda no próprio GitHub Pages, mantenha a exportação com **Shinylive**. O `app.R` convencional exige um servidor R; o Pages entrega os arquivos estáticos gerados pelo Shinylive. A comunicação com o Supabase foi implementada no JavaScript do navegador para funcionar também nessa exportação. Nenhum servidor R adicional é necessário ao usar Shinylive.

Exemplo de exportação, caso seu fluxo já use esse pacote:

```r
shinylive::export("caminho/para/escolas_sp_shiny", "site")
```

Se você roda Shiny em um serviço e incorpora a aplicação no seu site, os mesmos arquivos também podem ser usados.

## Usar no dia a dia

1. Clique em **Entrar** e use sua conta. A sessão fica somente na memória da aba: ao recarregar a página, entre novamente.
2. Aguarde a primeira consulta dos dados, selecione a escola e clique em **Editar natação**.
3. Preencha os três campos e clique em **Salvar dados**. Aguarde a confirmação de gravação.
4. A sócia pode usar outra conta, em outro computador. As duas acessam a mesma base.

Há filtros de piscina e estrutura, opção de colorir o mapa por piscina e inclusão dos novos campos na exportação. A base de escolas continua pública no projeto; o levantamento de natação exige login para consulta e edição.

Para corrigir um dado para desconhecido, use **Não informado** ou deixe a estimativa em branco e salve. O histórico da ficha informa a última alteração; este pacote não implementa um histórico de todas as versões no banco.

## Conferir depois de conectar

- Entre com cada conta e confirme que ambas veem o mesmo preenchimento.
- Salve uma escola com piscina, estrutura própria e um número de alunos; atualize na outra conta.
- Confira uma estimativa em branco e outra igual a zero.
- Abra a edição da mesma escola nos dois computadores; salve no primeiro e depois no segundo. A segunda gravação deve avisar o conflito.
- Saia da conta e confirme que o levantamento não está acessível.

## Referências técnicas

- [Shinylive para R: exportação para hospedagem estática](https://posit-dev.github.io/r-shinylive/)
- [Supabase: chaves de API](https://supabase.com/docs/guides/getting-started/api-keys)
- [Supabase: permissões por linha](https://supabase.com/docs/guides/database/postgres/row-level-security)
- [Supabase: funções no banco](https://supabase.com/docs/guides/database/functions)
