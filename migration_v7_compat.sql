-- v7 : correctif de compatibilité (à exécuter tout de suite, sans risque).
-- Une ancienne version de l'app, encore en cache chez certains utilisateurs, appelle request_book().
-- Cette fonction redirige vers la nouvelle logique (une demande à valider par l'admin).
-- Elle peut être supprimée plus tard : drop function if exists request_book(uuid);
create or replace function request_book(p_book uuid) returns void language plpgsql security definer as $$
begin perform request_borrow(p_book); end $$;
