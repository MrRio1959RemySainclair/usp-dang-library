-- v6 : une seule liste de demandes (plus de file séparée), un seul livre à la fois par membre.
-- À exécuter après migration_v5_perf.sql.
-- Les membres encore en file d'attente deviennent des demandes (s'ils n'en ont pas déjà une ni d'emprunt en cours).
insert into borrow_requests(book_id,user_id,created_at)
select distinct on (r.user_id) r.book_id,r.user_id,r.created_at from reservations r
where not exists(select 1 from borrow_requests q where q.user_id=r.user_id)
  and not exists(select 1 from loans l where l.user_id=r.user_id and l.returned_at is null)
order by r.user_id,r.created_at;
delete from reservations;

-- Seuls les emprunts en cours consomment le stock ; une demande n'en consomme pas
create or replace function free_copies(b uuid) returns int language sql security definer stable as $$
 select bk.copies-(select count(*)::int from loans l where l.book_id=b and l.returned_at is null) from books bk where bk.id=b $$;

-- Un membre : une seule demande OU un seul emprunt en cours (plus de limite mensuelle)
create or replace function request_borrow(p_book uuid) returns void language plpgsql security definer as $$
begin
 if exists(select 1 from loans where user_id=auth.uid() and returned_at is null) or exists(select 1 from borrow_requests where user_id=auth.uid()) then
  raise exception 'Vous avez déjà une demande ou un emprunt en cours : rapportez le livre avant d’en demander un autre.'; end if;
 if not exists(select 1 from books where id=p_book) then raise exception 'Livre introuvable.'; end if;
 insert into borrow_requests(book_id,user_id) values(p_book,auth.uid());
 insert into notifications(user_id,message) select p.id,'Nouvelle demande d’emprunt : « '||(select title from books where id=p_book)||' » par '||coalesce((select full_name from profiles where id=auth.uid()),'un membre')||'.' from profiles p where p.role='admin';
end $$;

-- Validation : possible seulement s'il reste un exemplaire ; le décompte démarre maintenant
create or replace function approve_request(p_req uuid) returns void language plpgsql security definer as $$
declare r borrow_requests; t text;
begin
 if not is_admin() then raise exception 'Accès refusé.'; end if;
 select * into r from borrow_requests where id=p_req for update;
 if not found then raise exception 'Demande introuvable.'; end if;
 if free_copies(r.book_id)<=0 then raise exception 'Aucun exemplaire disponible pour le moment.'; end if;
 delete from borrow_requests where id=p_req;
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
end $$;

create or replace function return_book(p_loan uuid) returns void language plpgsql security definer as $$
begin
 if not is_admin() then raise exception 'Accès refusé.'; end if;
 update loans set returned_at=now() where id=p_loan and returned_at is null;
end $$;

create or replace function sweep() returns void language plpgsql security definer as $$
begin
 with u as (update loans set reminded=true where returned_at is null and not reminded and due_at<now()+interval '3 days' and due_at>=now() returning user_id,book_id,due_at)
 insert into notifications(user_id,message) select u.user_id,'Rappel : « '||b.title||' » est à rendre le '||to_char(u.due_at,'DD/MM/YYYY')||'.' from u join books b on b.id=u.book_id;
 with u as (update loans set overdue_notified=true where returned_at is null and not overdue_notified and due_at<now() returning user_id,book_id)
 insert into notifications(user_id,message) select u.user_id,'En retard : merci de rendre « '||b.title||' ».' from u join books b on b.id=u.book_id;
end $$;

create or replace function books_guard() returns trigger language plpgsql security definer as $$
begin
 if new.copies<(select count(*) from loans where book_id=new.id and returned_at is null) then
  raise exception 'Stock inférieur au nombre d’exemplaires empruntés.'; end if;
 return new; end $$;

-- Suppression de l'ancien mécanisme de file / réservation
drop trigger if exists books_fill_t on books;
drop function if exists books_fill();
drop function if exists request_book(uuid);
drop function if exists fill_all();
drop function if exists fill_holds(uuid);
drop function if exists can_borrow(uuid);

drop function if exists catalog();
create function catalog() returns table(id uuid,title text,author text,cover_url text,description text,copies int,free int,next_due timestamptz,mine_req boolean,busy boolean,queue_count int) language sql security definer stable as $$
 select b.id,b.title,b.author,b.cover_url,b.description,b.copies,free_copies(b.id),
  (select min(l.due_at) from loans l where l.book_id=b.id and l.returned_at is null),
  exists(select 1 from borrow_requests q where q.book_id=b.id and q.user_id=auth.uid()),
  (exists(select 1 from loans l where l.user_id=auth.uid() and l.returned_at is null) or exists(select 1 from borrow_requests q where q.user_id=auth.uid())),
  (select count(*)::int from borrow_requests q where q.book_id=b.id)
 from books b order by b.title $$;
