-- v8 : un membre peut garder un livre ET faire une demande (une seule à la fois).
-- La demande n'est validable par l'admin qu'après le retour du livre en cours. À exécuter après migration_v6.sql.
create or replace function request_borrow(p_book uuid) returns void language plpgsql security definer as $$
declare has_loan boolean;
begin
 select exists(select 1 from loans where user_id=auth.uid() and returned_at is null) into has_loan;
 if exists(select 1 from borrow_requests where user_id=auth.uid()) then
  if has_loan then raise exception 'Vous avez déjà un emprunt non rendu et une demande en cours : rapportez le livre avant d’en demander un autre.';
  else raise exception 'Vous avez déjà une demande en cours : une seule demande à la fois.'; end if;
 end if;
 if exists(select 1 from loans where user_id=auth.uid() and book_id=p_book and returned_at is null) then raise exception 'Vous avez déjà ce livre en votre possession.'; end if;
 if not exists(select 1 from books where id=p_book) then raise exception 'Livre introuvable.'; end if;
 insert into borrow_requests(book_id,user_id) values(p_book,auth.uid());
 insert into notifications(user_id,message) select p.id,'Nouvelle demande d’emprunt : « '||(select title from books where id=p_book)||' » par '||coalesce((select full_name from profiles where id=auth.uid()),'un membre')||'.' from profiles p where p.role='admin';
end $$;

create or replace function approve_request(p_req uuid) returns void language plpgsql security definer as $$
declare r borrow_requests; t text;
begin
 if not is_admin() then raise exception 'Accès refusé.'; end if;
 select * into r from borrow_requests where id=p_req for update;
 if not found then raise exception 'Demande introuvable.'; end if;
 if exists(select 1 from loans where user_id=r.user_id and returned_at is null) then raise exception 'Ce membre n’a pas encore rapporté son livre.'; end if;
 if free_copies(r.book_id)<=0 then raise exception 'Aucun exemplaire disponible pour le moment.'; end if;
 delete from borrow_requests where id=p_req;
 insert into loans(book_id,user_id,borrowed_at,due_at) values(r.book_id,r.user_id,now(),now()+interval '14 days');
 select title into t from books where id=r.book_id;
 perform notify(r.user_id,'Votre demande pour « '||t||' » est validée. Retour prévu le '||to_char(now()+interval '14 days','DD/MM/YYYY')||'.');
end $$;

drop function if exists catalog();
create function catalog() returns table(id uuid,title text,author text,cover_url text,description text,copies int,free int,next_due timestamptz,mine_req boolean,mine_loan boolean,busy boolean,has_loan boolean,queue_count int) language sql security definer stable as $$
 select b.id,b.title,b.author,b.cover_url,b.description,b.copies,free_copies(b.id),
  (select min(l.due_at) from loans l where l.book_id=b.id and l.returned_at is null),
  exists(select 1 from borrow_requests q where q.book_id=b.id and q.user_id=auth.uid()),
  exists(select 1 from loans l where l.book_id=b.id and l.user_id=auth.uid() and l.returned_at is null),
  exists(select 1 from borrow_requests q where q.user_id=auth.uid()),
  exists(select 1 from loans l where l.user_id=auth.uid() and l.returned_at is null),
  (select count(*)::int from borrow_requests q where q.book_id=b.id)
 from books b order by b.title $$;
