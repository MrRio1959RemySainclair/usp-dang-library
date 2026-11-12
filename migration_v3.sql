-- v3 : stock par titre, zéro doublon, modification des livres, couvertures en fichier.
-- Base existante (v2) : exécuter ce fichier seul. Nouvelle base : schema.sql puis ce fichier.
alter table books add column if not exists copies int not null default 1 check (copies>=0);

-- Fusion des doublons existants (même titre + même auteur) : 1 ligne = 1 exemplaire
do $$ declare r record; ids uuid[]; k uuid;
begin
 for r in select lower(trim(title)) t, lower(trim(coalesce(author,''))) a, count(*) n from books group by 1,2 having count(*)>1 loop
  select array_agg(id order by created_at,id) into ids from books where lower(trim(title))=r.t and lower(trim(coalesce(author,'')))=r.a;
  k:=ids[1];
  update books set copies=r.n, cover_url=coalesce(cover_url,(select cover_url from books where id=any(ids) and cover_url is not null limit 1)), description=coalesce(description,(select description from books where id=any(ids) and description is not null limit 1)) where id=k;
  delete from reservations a using reservations b where a.book_id=any(ids) and b.book_id=any(ids) and a.user_id=b.user_id and (a.created_at,a.id)>(b.created_at,b.id);
  update loans set book_id=k where book_id=any(ids) and book_id<>k;
  update reservations set book_id=k where book_id=any(ids) and book_id<>k;
  delete from books where id=any(ids) and id<>k;
 end loop;
end $$;
create unique index if not exists books_uniq on books (lower(trim(title)), lower(trim(coalesce(author,''))));

create or replace function free_copies(b uuid) returns int language sql security definer stable as $$
 select bk.copies-(select count(*)::int from loans l where l.book_id=b and l.returned_at is null)-(select count(*)::int from reservations r where r.book_id=b and r.hold_until is not null) from books bk where bk.id=b $$;

create or replace function fill_holds(b uuid) returns void language plpgsql security definer as $$
declare r reservations; t text;
begin
 select title into t from books where id=b;
 while free_copies(b)>0 loop
  select * into r from reservations where book_id=b and hold_until is null order by created_at limit 1;
  exit when not found;
  update reservations set hold_until=now()+interval '3 days' where id=r.id;
  perform notify(r.user_id,'« '||t||' » est disponible pour vous. Venez le retirer avant le '||to_char(now()+interval '3 days','DD/MM/YYYY')||'.');
 end loop;
end $$;

create or replace function borrow_book(p_book uuid) returns void language plpgsql security definer as $$
declare h reservations;
begin
 if exists(select 1 from loans where user_id=auth.uid() and (returned_at is null or date_trunc('month',borrowed_at)=date_trunc('month',now()))) then raise exception 'Limite atteinte : un seul livre par mois.'; end if;
 select * into h from reservations where book_id=p_book and user_id=auth.uid() and hold_until is not null;
 if not found and free_copies(p_book)<=0 then raise exception 'Aucun exemplaire disponible.'; end if;
 delete from reservations where book_id=p_book and user_id=auth.uid();
 insert into loans(book_id,user_id,due_at) values(p_book,auth.uid(),now()+interval '14 days');
end $$;

create or replace function request_book(p_book uuid) returns void language plpgsql security definer as $$
begin
 if free_copies(p_book)>0 then raise exception 'Des exemplaires sont disponibles : empruntez-le directement.'; end if;
 insert into reservations(book_id,user_id) values(p_book,auth.uid()) on conflict do nothing;
end $$;

create or replace function return_book(p_loan uuid) returns void language plpgsql security definer as $$
declare l loans;
begin
 if not is_admin() then raise exception 'Accès refusé.'; end if;
 update loans set returned_at=now() where id=p_loan and returned_at is null returning * into l;
 if found then perform fill_holds(l.book_id); end if;
end $$;

create or replace function sweep() returns void language plpgsql security definer as $$
declare r record;
begin
 for r in with d as (delete from reservations where hold_until<now() returning book_id,user_id) select * from d loop
  perform notify(r.user_id,'Votre réservation a expiré.');
 end loop;
 for r in select distinct book_id from reservations where hold_until is null loop perform fill_holds(r.book_id); end loop;
 with u as (update loans set reminded=true where returned_at is null and not reminded and due_at<now()+interval '3 days' and due_at>=now() returning user_id,book_id,due_at)
 insert into notifications(user_id,message) select u.user_id,'Rappel : « '||b.title||' » est à rendre le '||to_char(u.due_at,'DD/MM/YYYY')||'.' from u join books b on b.id=u.book_id;
 with u as (update loans set overdue_notified=true where returned_at is null and not overdue_notified and due_at<now() returning user_id,book_id)
 insert into notifications(user_id,message) select u.user_id,'En retard : merci de rendre « '||b.title||' ».' from u join books b on b.id=u.book_id;
end $$;

drop function if exists promote_next(uuid);
drop function if exists catalog();
create function catalog() returns table(id uuid,title text,author text,cover_url text,description text,copies int,free int,next_due timestamptz,mine_hold boolean,queue_count int,my_pos int) language sql security definer stable as $$
 select b.id,b.title,b.author,b.cover_url,b.description,b.copies,free_copies(b.id),
  (select min(l.due_at) from loans l where l.book_id=b.id and l.returned_at is null),
  exists(select 1 from reservations r where r.book_id=b.id and r.hold_until is not null and r.user_id=auth.uid()),
  (select count(*)::int from reservations r where r.book_id=b.id and r.hold_until is null),
  (select x.p::int from (select user_id,row_number() over(order by created_at) p from reservations where book_id=b.id and hold_until is null) x where x.user_id=auth.uid())
 from books b order by b.title $$;

-- Le stock ne peut pas descendre sous les exemplaires prêtés/réservés ; une hausse de stock sert la file d'attente
create or replace function books_guard() returns trigger language plpgsql security definer as $$
begin
 if new.copies<(select count(*) from loans where book_id=new.id and returned_at is null)+(select count(*) from reservations where book_id=new.id and hold_until is not null) then
  raise exception 'Stock inférieur aux exemplaires empruntés ou réservés.'; end if;
 return new; end $$;
create or replace function books_fill() returns trigger language plpgsql security definer as $$
begin perform fill_holds(new.id); return new; end $$;
drop trigger if exists books_guard_t on books; drop trigger if exists books_fill_t on books;
create trigger books_guard_t before update of copies on books for each row execute function books_guard();
create trigger books_fill_t after update of copies on books for each row execute function books_fill();

-- Couvertures : fichiers envoyés par l'admin depuis l'app
insert into storage.buckets(id,name,public) values('covers','covers',true) on conflict (id) do nothing;
drop policy if exists cov_read on storage.objects; drop policy if exists cov_ins on storage.objects; drop policy if exists cov_upd on storage.objects; drop policy if exists cov_del on storage.objects;
create policy cov_read on storage.objects for select using (bucket_id='covers');
create policy cov_ins on storage.objects for insert to authenticated with check (bucket_id='covers' and is_admin());
create policy cov_upd on storage.objects for update to authenticated using (bucket_id='covers' and is_admin());
create policy cov_del on storage.objects for delete to authenticated using (bucket_id='covers' and is_admin());
