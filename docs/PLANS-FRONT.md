# USP-Dang Library — Plans du front (v2 cible)

Méthode (comme ZTF Imitators) : structure → design → icônes → fonctionnalités, par itérations. Mobile-first, PWA installable, Supabase (données + auth), GitHub → Netlify (déploiement automatique).

## 1. Plan du site (routes)

| Zone | Route | Écran |
|---|---|---|
| Public | `#/connexion` · `#/inscription` | Authentification |
| Membre | `#/` | Catalogue (recherche + filtres) |
| Membre | `#/livre/:id` | Détail du livre, file d'attente |
| Membre | `#/emprunt` | Mon emprunt + progression + mes demandes |
| Membre | `#/alertes` | Notifications |
| Membre | `#/profil` | Compte, langue, thème, installer l'app |
| Admin | `#/admin` | Vue d'ensemble (chiffres, retards, graphes) |
| Admin | `#/admin/livres` · `/emprunts` · `/file` · `/membres` · `/rapports` | Gestion et rapports |

Navigation membre : barre basse 4 onglets (Catalogue · Emprunt · Alertes · Profil), pastille sur Alertes.
Navigation admin : barre latérale sur ordinateur, onglets défilants sur mobile.

## 2. Maquettes (mobile)

```
CONNEXION                    CATALOGUE
┌────────────────────────┐   ┌────────────────────────┐
│        [logo]          │   │ [logo] USP-Dang   🔔 2 │
│   USP-Dang Library     │   │ 🔍 Rechercher un livre │
│ ┌Connexion|Créer──────┐│   │ (Tous)(Dispo)(Empruntés)│
│ E-mail  [__________]   │   │ ┌────────────────────┐ │
│ Mot de passe [_____]   │   │ │▭ Titre du livre    │ │
│ [   Se connecter   ]   │   │ │  Auteur            │ │
│ Installer l'app ⬇      │   │ │ ● Disponible [Emprunter]│
└────────────────────────┘   │ └────────────────────┘ │
                             │ ┌────────────────────┐ │
MON EMPRUNT                  │ │▭ Autre titre       │ │
┌────────────────────────┐   │ │ ● Emprunté → 17 nov│ │
│ Mon emprunt            │   │ │ 2 en attente [Demander]│
│ ┌────────────────────┐ │   │ └────────────────────┘ │
│ │ Titre · Auteur     │ │   ├────────────────────────┤
│ │ 03 nov → 17 nov    │ │   │ Catalogue Emprunt Alertes Profil│
│ │ ████████░░░░  58 % │ │   └────────────────────────┘
│ │ 6 jours restants   │ │
│ └────────────────────┘ │   ADMIN · VUE D'ENSEMBLE
│ Mes demandes           │   ┌────────────────────────┐
│ • Titre B — file n°2   │   │ [Livres][Dispo][Membres]│
│   [Annuler]            │   │ [Emprunts][Retards][File]│
└────────────────────────┘   │ ◔ Répartition des livres│
                             │ ▁▃▅▇ Emprunts / mois    │
PROFIL                       │ Retards : Titre — Nom   │
┌────────────────────────┐   │ [Retour] [Rappeler]     │
│ (avatar) Nom           │   └────────────────────────┘
│ Langue   [FR | EN]     │
│ Thème    [☀ | 🌙]      │
│ [Installer l'application]│
│ [Déconnexion]          │
└────────────────────────┘
```

## 3. Design (orange / blanc, doux)

- Couleurs clair : fond `#FFFAF5`, surface `#FFFFFF`, orange `#F28C38`, orange foncé `#E8741A`, teinte `#FFF1E4`, texte `#2B2118`, bordure `#F3E4D6`.
- Couleurs sombre : fond `#1E1612`, surface `#2A201A`, orange `#F59A4A`, texte `#F6EDE4`.
- Statuts : disponible vert `#2F9E6B` · emprunté orange · réservé ambre `#D9480F` · retard rouge `#C92A2A`.
- Typographie : Nunito (400 / 600 / 700). Rayons 16 px, boutons en pilule, ombres chaudes très légères.
- Mouvements : survol et appui sur les cartes, barre de progression animée, graphes animés à l'apparition.

## 4. Composants

AppBar · BottomNav · SideNav (admin) · SearchBar · FilterChips · BookCard · StatusBadge · ProgressBar · QueueChip · NotificationItem · StatTile · DataTable · DonutChart · BarChart · Sheet/Modal · Toast · EmptyState · Skeleton · InstallButton · UpdateBanner · LangSwitch · ThemeSwitch.

## 5. Icônes à fournir (SVG 24×24, trait uniforme, `currentColor`) → `assets/icons/<nom>.svg`

- Navigation : `catalogue`, `emprunt`, `alertes`, `profil`
- Admin : `livres`, `emprunts`, `file`, `membres`, `rapports`
- Actions : `emprunter`, `demander`, `retour`, `ajouter`, `supprimer`, `rechercher`, `installer`, `mise-a-jour`, `langue`, `soleil`, `lune`, `deconnexion`
- Statuts : `disponible`, `emprunte`, `reserve`, `retard`
- Logo : `logo.svg` + PNG 192 × 192 et 512 × 512 (+ version maskable)
- Illustrations (facultatif) : catalogue vide, aucune alerte, aucun emprunt

## 6. Écrans → données Supabase

Catalogue → `catalog()` · Emprunter → `borrow_book` · Demander → `request_book` · Mon emprunt → `loans`, `reservations` · Alertes → `notifications` (temps réel) · Retour (admin) → `return_book` · Rappels et expirations → `sweep()` · Rapports → `books`, `loans`, `reservations`, `profiles`.

## 7. État d'avancement

Livré (v2) : routes `#/…` + barre basse (barre latérale sur ordinateur) + détail livre · recherche et filtres · logo, icônes d'interface (SVG intégrés) et couvertures · thème clair/sombre + FR/EN · bouton « Installer » + bannière « Mise à jour » · page Membres, donut et histogramme animés · export PDF des rapports (impression du navigateur).
Reste : icônes personnalisées (remplacer le jeu SVG intégré dans `index.html`, objet `P`), illustrations d'états vides, squelettes de chargement, traduction des messages renvoyés par la base (encore en français).

## 8. Workflow

Dépôt GitHub → Netlify (déploiement automatique à chaque push) · Supabase pour la base · tu pousses toi-même ; avant chaque livraison, je clone le dépôt à neuf et je compare avec tes modifications.
