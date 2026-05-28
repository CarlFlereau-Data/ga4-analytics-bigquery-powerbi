# 🛍️ GA4 E-commerce Analytics — BigQuery × Power BI

> Analyse end-to-end du comportement d'achat sur le **Google Merchandise Store**, du modèle SQL en étoile sur BigQuery jusqu'au dashboard Power BI.

## 📌 Résumé du projet

Ce projet exploite le jeu de données public **`bigquery-public-data.ga4_obfuscated_sample_ecommerce`** (données Google Analytics 4 du Google Merchandise Store) pour construire une plateforme analytique complète couvrant l'acquisition, le comportement, la conversion, l'e-commerce et la rétention.

L'objectif est de démontrer une chaîne de valeur **data engineering → modélisation → analytics → restitution** sur un cas réel : structures d'événements imbriquées (`event_params`), modèle en étoile, mesures DAX avancées, et une couche optionnelle d'insights IA via l'API Claude.

**Période analysée :** octobre 2020 → février 2021
**Volumétrie :** ~270 000 utilisateurs · ~360 000 sessions · 214 K$ de revenu

---

## 🏗️ Architecture

```
┌─────────────────────┐     ┌──────────────────────┐     ┌─────────────────────┐
│   BigQuery (GA4)     │     │   Modèle en étoile   │     │      Power BI       │
│  Données brutes GA4  │ ──► │   8 vues SQL         │ ──► │  Import + DAX       │
│  events_* (nested)   │     │  Faits + Dimensions  │     │  5 pages dashboard  │
└─────────────────────┘     └──────────────────────┘     └─────────────────────┘
        UNNEST                    SQL-first                   Star schema
     event_params              transformations              9 relations N:1
```

### Philosophie SQL-first
Toutes les transformations lourdes sont réalisées en **SQL dans BigQuery**. Power Query est volontairement limité à la validation des types et au renommage, garantissant des performances optimales en mode Import et une logique métier centralisée et versionnable.

---

## 🗂️ Modèle de données (Star Schema)

Le modèle repose sur **3 tables de faits** et **5 dimensions**, reliées par 9 relations many-to-one à sens de filtre unique.

| Type | Vue BigQuery | Rôle |
|------|--------------|------|
| **Fait** | `vw_fact_events` | Événements GA4 (géo + device intégrés) |
| **Fait** | `vw_fact_purchases` | Lignes de transaction (grain produit) |
| **Fait** | `vw_fact_sessions_funnel` | Étapes du tunnel par session |
| Dimension | `vw_dim_date` | Table de dates (marquée comme date table) |
| Dimension | `vw_dim_user` | Utilisateurs + attributs first-touch |
| Dimension | `vw_dim_session` | Sessions + cohorte hebdomadaire |
| Dimension | `vw_dim_product` | Produits (mode-based dedup) |
| Dimension | *product parent* | Regroupement produit parent |
---

## 📊 Pages du dashboard

### 1. Overview
KPIs globaux (utilisateurs, sessions, taux de conversion, revenu, panier moyen), tendance des sessions avec moyenne mobile 7 jours, répartition par device, revenu mensuel, top produits et marques.

### 2. Acquisition
Sessions par mois et par canal (stacked bar), taux de conversion et revenu par couple canal × source, classement des campagnes par revenu attribué.

### 3. Behavior
Pages vues par session, taux d'usage de la recherche, volume des événements clés, répartition horaire `add_to_cart` vs `purchase`, pages les plus consultées.

### 4. Funnel Analysis
Tunnel de conversion à 5 étapes (`view_item → add_to_cart → begin_checkout → add_payment_info → purchase`), taux de passage inter-étapes, comparaison Desktop vs Mobile, taux d'abandon panier.

### 5. Cohort Analysis (Retention / LTV)
Rétention hebdomadaire par cohorte (triangle de rétention), LTV moyenne, segmentation client (One-time / Regular / VIP), revenu par segment, taux de prospects.

---

## 🧮 Mesures DAX clés

Plus de 30 mesures construites, dont :

- **Taux de conversion** (sessions converties / sessions totales)
- **Total Revenue** — déduplication via `SUMX(VALUES(transaction_id), CALCULATE(MAX(...)))` pour éviter le double-comptage
- **Comparaisons MoM** et moyennes mobiles 7 jours
- **Taux de passage du tunnel** (Cart→Checkout, Checkout→Payment, Payment→Purchase)
- **Rétention de cohorte** hebdomadaire
- **Avg LTV / Avg LTV per User / Avg Purchases per Buyer**
- **Cart Abandonment Rate**, **Engagement Rate**, **Search Usage Rate**

---

## 🐛 Défis techniques résolus

| Problème | Cause | Solution |
|----------|-------|----------|
| **86 % d'événements perdus** | Filtre `debug_mode` mal interprété | `COALESCE` pour traiter les NULL |
| **`ANY_VALUE` + `IGNORE NULLS`** | Incompatibilité BigQuery | `ARRAY_AGG(... IGNORE NULLS ORDER BY ... LIMIT 1)[SAFE_OFFSET(0)]` |
| **Doublons `vw_dim_product`** | `SELECT DISTINCT` sur tous les attributs | Agrégation par mode via `ROW_NUMBER() OVER (PARTITION BY item_id ORDER BY COUNT(*) DESC)` |
| **Échec clause `USING`** | Renommage de colonnes dans les CTE | Jointures explicites en `ON` |
| **Casse Power Query** | `user_first_medium` vs `first_medium` | Cohérence stricte des noms SQL ↔ Power Query |
| **Tunnel produit peu fiable** | `view_item` (426 ids) vs `purchase` (809 ids) | Colonne `tracking_status` (Full / Purchased only / Viewed only) |

## 🚀 Reproduire le projet

1. Accéder au dataset public `bigquery-public-data.ga4_obfuscated_sample_ecommerce`.
2. Exécuter les vues SQL du dossier `sql/` dans votre projet BigQuery.
3. Connecter Power BI Desktop en mode **Import** aux 8 vues.
4. Recréer les 9 relations N:1 (sens de filtre unique) et marquer `vw_dim_date` comme table de dates.
5. Importer / recréer les mesures DAX (`dax/`).

---

## 📁 Structure du dépôt

```
.
├── README.md
├── sql/                  # Vues BigQuery (star schema)
├── dax/                  # Mesures DAX
├── docs/                 # Rapport analytique (PDF)
└── assets/
    └── screenshots/      # Captures du dashboard
```

---

## 📄 Licence

Données issues du dataset public Google Analytics 4 sample.

---

*Projet portfolio — Data Engineering & Analytics · Carl Flereau*
