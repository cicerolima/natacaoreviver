-- Execute no SQL Editor do SEU projeto Supabase.
-- Cadastro de natação separado da base original, com uma linha por código INEP.
begin;

create table if not exists public.nv_editores (
  user_id uuid primary key references auth.users(id) on delete cascade,
  nome text not null check (length(trim(nome)) between 1 and 120)
);

create table if not exists public.nv_natacao (
  inep text primary key check (inep ~ '^[0-9]{8}$'),
  tem_piscina boolean,
  estrutura text check (estrutura in ('Própria', 'Terceirizada', 'Não se aplica')),
  alunos_natacao integer check (alunos_natacao >= 0),
  versao bigint not null default 1 check (versao >= 1),
  atualizado_em timestamptz not null default now(),
  atualizado_por text not null,
  usuario_id uuid not null references auth.users(id)
);

alter table public.nv_editores enable row level security;
alter table public.nv_natacao enable row level security;
revoke all on public.nv_editores from public, anon, authenticated;
revoke all on public.nv_natacao from public, anon, authenticated;
grant select on public.nv_editores to authenticated;
grant select on public.nv_natacao to authenticated;

drop policy if exists nv_consultar_proprio_acesso on public.nv_editores;
create policy nv_consultar_proprio_acesso on public.nv_editores
  for select to authenticated using (user_id = (select auth.uid()));

drop policy if exists nv_consultar_natacao on public.nv_natacao;
create policy nv_consultar_natacao on public.nv_natacao
  for select to authenticated using (
    exists (select 1 from public.nv_editores e where e.user_id = (select auth.uid()))
  );

-- A escrita só ocorre por esta função: valida o acesso e a versão em uma transação.
-- Uma edição não sobrescreve silenciosamente outra que foi salva antes.
create or replace function public.nv_salvar_natacao(
  p_inep text, p_tem_piscina boolean, p_estrutura text,
  p_alunos_natacao integer, p_versao_esperada bigint
)
returns setof public.nv_natacao
language plpgsql security definer set search_path = ''
as $$
declare
  v_usuario uuid := auth.uid();
  v_nome text;
  v_registro public.nv_natacao%rowtype;
begin
  select e.nome into v_nome from public.nv_editores e where e.user_id = v_usuario;
  if v_usuario is null or v_nome is null then
    raise exception 'SEM_PERMISSAO' using errcode = '42501';
  end if;
  if p_inep is null or p_inep !~ '^[0-9]{8}$' or
     p_versao_esperada is null or p_versao_esperada < 0 then
    raise exception 'REGISTRO_INVALIDO' using errcode = '22023';
  end if;
  if p_estrutura is not null and p_estrutura not in ('Própria', 'Terceirizada', 'Não se aplica') then
    raise exception 'ESTRUTURA_INVALIDA' using errcode = '22023';
  end if;
  if p_alunos_natacao is not null and p_alunos_natacao < 0 then
    raise exception 'ALUNOS_INVALIDOS' using errcode = '22023';
  end if;

  if p_versao_esperada = 0 then
    insert into public.nv_natacao
      (inep, tem_piscina, estrutura, alunos_natacao, versao, atualizado_em, atualizado_por, usuario_id)
    values
      (p_inep, p_tem_piscina, p_estrutura, p_alunos_natacao, 1, clock_timestamp(), v_nome, v_usuario)
    on conflict (inep) do nothing returning * into v_registro;
  else
    update public.nv_natacao n set
      tem_piscina = p_tem_piscina, estrutura = p_estrutura,
      alunos_natacao = p_alunos_natacao, versao = n.versao + 1,
      atualizado_em = clock_timestamp(), atualizado_por = v_nome, usuario_id = v_usuario
    where n.inep = p_inep and n.versao = p_versao_esperada
    returning n.* into v_registro;
  end if;

  if not found then
    raise exception 'CONFLITO_EDICAO' using errcode = '40001';
  end if;
  return next v_registro;
end;
$$;

revoke all on function public.nv_salvar_natacao(text, boolean, text, integer, bigint)
  from public, anon, authenticated;
grant execute on function public.nv_salvar_natacao(text, boolean, text, integer, bigint)
  to authenticated;
commit;
