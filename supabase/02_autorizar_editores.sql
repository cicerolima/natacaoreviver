-- Antes de executar: crie as duas contas em Authentication > Users no Supabase.
-- Substitua os e-mails e os nomes abaixo pelos seus dados.
-- Execute no SQL Editor. O aplicativo não permite cadastro público de editores.
insert into public.nv_editores (user_id, nome)
select u.id, dados.nome
from (values
  ('czlima@gmail.com', 'Cicero Lima'),
  ('phablynas@gmail.com', 'Phablyna Sousa')
) as dados(email, nome)
join auth.users u on lower(u.email) = lower(dados.email)
on conflict (user_id) do update set nome = excluded.nome;

-- Confira se aparecem exatamente as duas contas que vocês querem autorizar.
select e.nome, u.email from public.nv_editores e
join auth.users u on u.id = e.user_id order by e.nome;
