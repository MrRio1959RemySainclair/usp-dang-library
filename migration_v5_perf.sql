-- v5 : performances. À exécuter après migration_v4.sql (sans risque, peut être relancé).
-- 1) Index sur les colonnes les plus filtrées
create index if not exists loans_book_active on loans(book_id) where returned_at is null;
create index if not exists loans_user on loans(user_id);
create index if not exists res_book on reservations(book_id);
create index if not exists res_user on reservations(user_id);
create index if not exists req_book on borrow_requests(book_id);
create index if not exists notif_user on notifications(user_id, created_at desc);
-- 2) Politiques RLS : auth.uid() et is_admin() évalués une seule fois par requête (et non par ligne)
drop policy if exists p_sel on profiles;  create policy p_sel on profiles for select using (id=(select auth.uid()) or (select is_admin()));
drop policy if exists b_adm on books;     create policy b_adm on books for all using ((select is_admin())) with check ((select is_admin()));
drop policy if exists l_sel on loans;     create policy l_sel on loans for select using (user_id=(select auth.uid()) or (select is_admin()));
drop policy if exists r_sel on reservations; create policy r_sel on reservations for select using (user_id=(select auth.uid()) or (select is_admin()));
drop policy if exists r_del on reservations; create policy r_del on reservations for delete using (user_id=(select auth.uid()) or (select is_admin()));
drop policy if exists n_sel on notifications; create policy n_sel on notifications for select using (user_id=(select auth.uid()));
drop policy if exists n_upd on notifications; create policy n_upd on notifications for update using (user_id=(select auth.uid()));
drop policy if exists rq_sel on borrow_requests; create policy rq_sel on borrow_requests for select using (user_id=(select auth.uid()) or (select is_admin()));
