-- v4 : l'admin valide chaque demande d'emprunt (le décompte démarre à la validation),
-- une seule demande/un seul emprunt à la fois par membre, file d'attente toujours ouverte.
-- À exécuter après migration_v3.sql.
create table if not exists borrow_requests(id uuid primary key default gen_random_uuid(), book_id uuid not null references books on delete cascade, user_id uuid not null unique references profiles on delete cascade, created_at timestamptz default now());
alter table borrow_requests enable row level security;
drop policy if exists rq_sel on borrow_requests;
create policy rq_sel on borrow_requests for select using (user_id=auth.uid() or is_admin());

-- Un exemplaire demandé (en attente de validation) est déjà réservé pour le membre
create or replace function free_copies(b uuid) returns int language sql security definer stable as $$
 select bk.copies-(select count(*)::int from loans l where l.book_id=b and l.returned_at is null)-(select count(*)::int from reservations r where r.book_id=b and r.hold_until is not null)-(select count(*)::int from borrow_requests q where q.book_id=b) from books bk where bk.id=b $$;

create or replace function can_borrow(u uuid) returns boolean language sql security definer stable as $$
 select not exists(select 1 from loans where user_id=u and (returned_at is null or date_trunc('month',borrowed_at)=date_trunc('month',now())))
  and not exists(select 1 from borrow_requests where user_id=u) $$;

-- Seuls les membres en mesure d'emprunter passent de la file à une réservation de 3 jours
create or replace function fill_holds(b uuid) returns void language plpgsql security definer as $$
declare r reservations; t text;
begin
 select title into t from books where id=b;
 while free_copies(b)>0 loop
  select * into r from reservations rs where rs.book_id=b and rs.hold_until is null and can_borrow(rs.user_id)
   and not exists(select 1 from reservations h where h.user_id=rs.user_id and h.hold_until is not null) order by rs.created_at limit 1;
  exit when not found;
  update reservations set hold_until=now()+interval '3 days' where id=r.id;
  perform notify(r.user_id,'« '||t||' » est disponible pour vous. Faites votre demande d’emprunt avant le '||to_char(now()+interval '3 days','DD/MM/YYYY')||'.');
 end loop;
end $$;
create or replace function fill_all() returns void language plpgsql security definer as $$
declare x uuid;
begin for x in select distinct book_id from reservations where hold_until is null loop perform fill_holds(x); end loop; end $$;

drop function if exists borrow_book(uuid);
create or replace function request_borrow(p_book uuid) returns void language plpgsql security definer as $$
declare h reservations;
begin
 if exists(select 1 from borrow_requests where user_id=auth.uid() and book_id=p_book) then raise exception 'Vous avez déjà demandé ce livre.'; end if;
 if exists(select 1 from loans where user_id=auth.uid() and returned_at is null) or exists(select 1 from borrow_requests where user_id=auth.uid()) then
  raise exception 'Vous avez déjà une demande ou un emprunt en cours : rapportez-le avant d’en demander un autre.'; end if;
 if exists(select 1 from loans where user_id=auth.uid() and date_trunc('month',borrowed_at)=date_trunc('month',now())) then raise exception 'Limite atteinte : un seul livre par mois.'; end if;
 select * into h from reservations where book_id=p_book and user_id=auth.uid() and hold_until is not null;
 if not found and free_copies(p_book)<=0 then raise exception 'Aucun exemplaire disponible.'; end if;
 delete from reservations where book_id=p_book and user_id=auth.uid();
 insert into borrow_requests(book_id,user_id) values(p_book,auth.uid());
 insert into notifications(user_id,message) select p.id,'Nouvelle demande d’emprunt : « '||(select title from books where id=p_book)||' » par '||coalesce((select full_name from profiles where id=auth.uid()),'un membre')||'.' from profiles p where p.role='admin';
end $$;

create or replace function approve_request(p_req uuid) returns void language plpgsql security definer as $$
declare r borrow_requests; t text;
begin
 if not is_admin() then raise exception 'Accès refusé.'; end if;
 delete from borrow_requests where id=p_req returning * into r;
 if not found then raise exception 'Demande introuvable.'; end if;
 insert into loans(book_id,user_id,borrowed_at,due_at) values(r.book_id,r.user_id,now(),now()+interval '14 days');
 select title into t from books where id=r.book_id;
 perform notify(r.user_id,'Votre demande pour « '||t||' » est validée. Retour prévu le '||to_char(now()+interval '14 days','DD/MM/YYYY')||'.');
end $$;

create or replace function reject_request(p_req uuid) returns void language plpgsql security definer as $$
declare r borrow_requests; t text;
begin
 if not is_admin() then raise exception 'Accès refusé.'; end if;
 delete from borrow_requests where id=p_req returning * into r;
 if not found then raise exception 'Demande introuvable.'; end if;
 select title into t from books where id=r.book_id;
 perform notify(r.user_id,'Votre demande pour « '||t||' » a été refusée.');
 perform fill_all();
end $$;

-- File d'attente : possible même quand on a déjà un emprunt ou une demande (sauf sur le livre concerné)
create or replace function request_book(p_book uuid) returns void language plpgsql security definer as $$
begin
 if exists(select 1 from borrow_requests where user_id=auth.uid() and book_id=p_book) or exists(select 1 from loans where user_id=auth.uid() and book_id=p_book and returned_at is null) then
  raise exception 'Vous avez déjà ce livre ou une demande pour ce livre.'; end if;
 if free_copies(p_book)>0 and can_borrow(auth.uid()) then raise exception 'Des exemplaires sont disponibles : demandez à l’emprunter directement.'; end if;
 insert into reservations(book_id,user_id) values(p_book,auth.uid()) on conflict do nothing;
end $$;

create or replace function return_book(p_loan uuid) returns void language plpgsql security definer as $$
declare l loans;
begin
 if not is_admin() then raise exception 'Accès refusé.'; end if;
 update loans set returned_at=now() where id=p_loan and returned_at is null returning * into l;
 if found then perform fill_all(); end if;
end $$;

create or replace function books_guard() returns trigger language plpgsql security definer as $$
begin
 if new.copies<(select count(*) from loans where book_id=new.id and returned_at is null)+(select count(*) from reservations where book_id=new.id and hold_until is not null)+(select count(*) from borrow_requests where book_id=new.id) then
  raise exception 'Stock inférieur aux exemplaires empruntés, demandés ou réservés.'; end if;
 return new; end $$;

drop function if exists catalog();
create function catalog() returns table(id uuid,title text,author text,cover_url text,description text,copies int,free int,next_due timestamptz,mine_hold boolean,mine_req boolean,busy boolean,queue_count int,my_pos int) language sql security definer stable as $$
 select b.id,b.title,b.author,b.cover_url,b.description,b.copies,free_copies(b.id),
  (select min(l.due_at) from loans l where l.book_id=b.id and l.returned_at is null),
  exists(select 1 from reservations r where r.book_id=b.id and r.hold_until is not null and r.user_id=auth.uid()),
  exists(select 1 from borrow_requests q where q.book_id=b.id and q.user_id=auth.uid()),
  not can_borrow(auth.uid()),
  (select count(*)::int from reservations r where r.book_id=b.id and r.hold_until is null),
  (select x.p::int from (select user_id,row_number() over(order by created_at) p from reservations where book_id=b.id and hold_until is null) x where x.user_id=auth.uid())
 from books b order by b.title $$;
