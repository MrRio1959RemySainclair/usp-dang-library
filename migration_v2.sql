-- À exécuter UNE fois si la base v1 existe déjà (SQL Editor)
alter table books add column if not exists cover_url text;
alter table books add column if not exists description text;
alter table profiles add column if not exists email text;
update profiles p set email=u.email from auth.users u where u.id=p.id and p.email is null;
create or replace function handle_new_user() returns trigger language plpgsql security definer as $$
begin insert into profiles(id,full_name,email) values(new.id,new.raw_user_meta_data->>'full_name',new.email); return new; end $$;
drop function if exists catalog();
create function catalog() returns table(id uuid,title text,author text,cover_url text,description text,due_at timestamptz,held boolean,mine_hold boolean,queue_count int,my_pos int) language sql security definer stable as $$
 select b.id,b.title,b.author,b.cover_url,b.description,
  (select l.due_at from loans l where l.book_id=b.id and l.returned_at is null),
  exists(select 1 from reservations r where r.book_id=b.id and r.hold_until is not null),
  exists(select 1 from reservations r where r.book_id=b.id and r.hold_until is not null and r.user_id=auth.uid()),
  (select count(*)::int from reservations r where r.book_id=b.id),
  (select x.p::int from (select user_id,row_number() over(order by created_at) p from reservations where book_id=b.id) x where x.user_id=auth.uid())
 from books b order by b.title $$;
insert into books(title,author,cover_url) values
('Délivrance du péché d’adultère et de fornication','Zacharias Tannee Fomum','assets/covers/delivrance-adultere-fornication.jpg'),
('Délivrance du péché de la paresse','Zacharias Tannee Fomum','assets/covers/delivrance-paresse.jpg'),
('La délivrance du péché','Zacharias Tannee Fomum','assets/covers/delivrance-du-peche.jpg');
