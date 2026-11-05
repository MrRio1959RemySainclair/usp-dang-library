-- USP-Dang Library : à exécuter dans Supabase > SQL Editor
create table profiles(id uuid primary key references auth.users on delete cascade, full_name text, email text, role text not null default 'user');
create table books(id uuid primary key default gen_random_uuid(), title text not null, author text, cover_url text, description text, created_at timestamptz default now());
create table loans(id uuid primary key default gen_random_uuid(), book_id uuid not null references books on delete cascade, user_id uuid not null references profiles on delete cascade, borrowed_at timestamptz default now(), due_at timestamptz not null, returned_at timestamptz, reminded boolean default false, overdue_notified boolean default false);
create table reservations(id uuid primary key default gen_random_uuid(), book_id uuid not null references books on delete cascade, user_id uuid not null references profiles on delete cascade, created_at timestamptz default now(), hold_until timestamptz, unique(book_id,user_id));
create table notifications(id uuid primary key default gen_random_uuid(), user_id uuid not null references profiles on delete cascade, message text not null, read boolean default false, created_at timestamptz default now());

create function handle_new_user() returns trigger language plpgsql security definer as $$
begin insert into profiles(id,full_name,email) values(new.id,new.raw_user_meta_data->>'full_name',new.email); return new; end $$;
create trigger on_auth_user_created after insert on auth.users for each row execute function handle_new_user();

create function is_admin() returns boolean language sql security definer stable as $$
select exists(select 1 from profiles where id=auth.uid() and role='admin') $$;

alter table profiles enable row level security; alter table books enable row level security; alter table loans enable row level security;
alter table reservations enable row level security; alter table notifications enable row level security;
create policy p_sel on profiles for select using (id=auth.uid() or is_admin());
create policy b_sel on books for select to authenticated using (true);
create policy b_adm on books for all using (is_admin()) with check (is_admin());
create policy l_sel on loans for select using (user_id=auth.uid() or is_admin());
create policy r_sel on reservations for select using (user_id=auth.uid() or is_admin());
create policy r_del on reservations for delete using (user_id=auth.uid() or is_admin());
create policy n_sel on notifications for select using (user_id=auth.uid());
create policy n_upd on notifications for update using (user_id=auth.uid());

create function notify(u uuid, m text) returns void language sql security definer as $$ insert into notifications(user_id,message) values(u,m) $$;

create function promote_next(b uuid) returns void language plpgsql security definer as $$
declare r reservations; t text;
begin
 select * into r from reservations where book_id=b and hold_until is null order by created_at limit 1;
 if found then
  update reservations set hold_until=now()+interval '3 days' where id=r.id;
  select title into t from books where id=b;
  perform notify(r.user_id,'« '||t||' » est disponible pour vous. Venez le retirer avant le '||to_char(now()+interval '3 days','DD/MM/YYYY')||'.');
 end if;
end $$;

create function borrow_book(p_book uuid) returns void language plpgsql security definer as $$
declare h reservations;
begin
 if exists(select 1 from loans where user_id=auth.uid() and (returned_at is null or date_trunc('month',borrowed_at)=date_trunc('month',now()))) then raise exception 'Limite atteinte : un seul livre par mois.'; end if;
 if exists(select 1 from loans where book_id=p_book and returned_at is null) then raise exception 'Ce livre est indisponible.'; end if;
 select * into h from reservations where book_id=p_book and hold_until is not null;
 if found and h.user_id<>auth.uid() then raise exception 'Ce livre est réservé pour un autre membre.'; end if;
 delete from reservations where book_id=p_book and user_id=auth.uid();
 insert into loans(book_id,user_id,due_at) values(p_book,auth.uid(),now()+interval '14 days');
end $$;

create function request_book(p_book uuid) returns void language plpgsql security definer as $$
begin
 if not exists(select 1 from loans where book_id=p_book and returned_at is null) and not exists(select 1 from reservations where book_id=p_book and hold_until is not null) then
  raise exception 'Ce livre est disponible : empruntez-le directement.'; end if;
 insert into reservations(book_id,user_id) values(p_book,auth.uid()) on conflict do nothing;
end $$;

create function return_book(p_loan uuid) returns void language plpgsql security definer as $$
declare l loans;
begin
 if not is_admin() then raise exception 'Accès refusé.'; end if;
 update loans set returned_at=now() where id=p_loan and returned_at is null returning * into l;
 if found then perform promote_next(l.book_id); end if;
end $$;

-- Expire les réservations, envoie les rappels (appelée à l'ouverture de l'app ; planifiable avec pg_cron)
create function sweep() returns void language plpgsql security definer as $$
declare r record;
begin
 for r in with d as (delete from reservations where hold_until<now() returning book_id,user_id) select * from d loop
  perform notify(r.user_id,'Votre réservation a expiré.'); perform promote_next(r.book_id);
 end loop;
 with u as (update loans set reminded=true where returned_at is null and not reminded and due_at<now()+interval '3 days' and due_at>=now() returning user_id,book_id,due_at)
 insert into notifications(user_id,message) select u.user_id,'Rappel : « '||b.title||' » est à rendre le '||to_char(u.due_at,'DD/MM/YYYY')||'.' from u join books b on b.id=u.book_id;
 with u as (update loans set overdue_notified=true where returned_at is null and not overdue_notified and due_at<now() returning user_id,book_id)
 insert into notifications(user_id,message) select u.user_id,'En retard : merci de rendre « '||b.title||' ».' from u join books b on b.id=u.book_id;
end $$;

create function catalog() returns table(id uuid,title text,author text,cover_url text,description text,due_at timestamptz,held boolean,mine_hold boolean,queue_count int,my_pos int) language sql security definer stable as $$
 select b.id,b.title,b.author,b.cover_url,b.description,
  (select l.due_at from loans l where l.book_id=b.id and l.returned_at is null),
  exists(select 1 from reservations r where r.book_id=b.id and r.hold_until is not null),
  exists(select 1 from reservations r where r.book_id=b.id and r.hold_until is not null and r.user_id=auth.uid()),
  (select count(*)::int from reservations r where r.book_id=b.id),
  (select x.p::int from (select user_id,row_number() over(order by created_at) p from reservations where book_id=b.id) x where x.user_id=auth.uid())
 from books b order by b.title $$;

alter publication supabase_realtime add table notifications;
-- Pour devenir admin (remplacez l'e-mail) :
-- update profiles set role='admin' where id=(select id from auth.users where email='vous@exemple.com');

insert into books(title,author,cover_url) values
('Délivrance du péché d’adultère et de fornication','Zacharias Tannee Fomum','assets/covers/delivrance-adultere-fornication.jpg'),
('Délivrance du péché de la paresse','Zacharias Tannee Fomum','assets/covers/delivrance-paresse.jpg'),
('La délivrance du péché','Zacharias Tannee Fomum','assets/covers/delivrance-du-peche.jpg');
