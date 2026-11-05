# USP-Dang Library
PWA de gestion de bibliothèque (Supabase + Netlify).

1. Supabase > SQL Editor : nouvelle base → exécuter `schema.sql` ; base v1 déjà en place → exécuter `migration_v2.sql` à la place.
2. Dans `index.html`, renseigner `CFG.url` et `CFG.key` (clé anon publique).
3. Supabase > Authentication > URL Configuration : mettre l'URL Netlify en Site URL.
4. S'inscrire dans l'app, puis passer le compte en admin (requête commentée à la fin de `schema.sql`).
5. Pousser sur GitHub ; Netlify déploie automatiquement (publish directory : racine).

Plans du front : `docs/PLANS-FRONT.md`. Logo et icônes PWA : `assets/icons/`. Couvertures : `assets/covers/` (le champ `cover_url` d'un livre accepte un chemin relatif ou une URL).
