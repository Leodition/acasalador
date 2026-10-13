begin;
do $$
declare actor uuid; other_user uuid; rev integer; saved public.tefalei_individual_money; denied boolean:=false; leaked integer;
begin
 select id into actor from auth.users order by created_at limit 1;
 select id into other_user from auth.users where id<>actor order by created_at limit 1;
 if actor is null or other_user is null then raise exception 'Faltam contas para validar o isolamento';end if;
 select coalesce((select revision from public.tefalei_individual_money where user_id=actor),0) into rev;
 perform set_config('request.jwt.claim.sub',actor::text,true);
 execute 'set local role authenticated';
 saved:=public.tefalei_save_individual_money(1234.56,'[{"id":"teste","name":"Planejamento","items":[{"id":"fixo","desc":"Fixo de teste","value":100,"fixed":true}]}]'::jsonb,rev);
 if saved.income<>1234.56 or jsonb_array_length(saved.categories)<>1 then raise exception 'Dados não salvos';end if;
 perform set_config('request.jwt.claim.sub',other_user::text,true);
 select count(*) into leaked from public.tefalei_individual_money where user_id=actor;
 if leaked<>0 then raise exception 'Dados de outra conta expostos';end if;
 perform set_config('request.jwt.claim.sub',actor::text,true);
 begin perform public.tefalei_save_individual_money(9999,'[]'::jsonb,rev);exception when others then denied:=true;end;
 if not denied then raise exception 'Gravação antiga sobrescreveu dados novos';end if;
 execute 'reset role';
end;$$;
rollback;
select 'PASS: receita e planejamento persistidos; acesso individual protegido; conflito entre aparelhos bloqueado; dados de teste revertidos' as validacao;
