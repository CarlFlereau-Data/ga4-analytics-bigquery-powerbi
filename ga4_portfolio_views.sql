-- =====================================================================
-- Projet portfolio GA4 - modele en etoile (BigQuery)
-- Source : bigquery-public-data.ga4_obfuscated_sample_ecommerce

CREATE SCHEMA IF NOT EXISTS `projet-ga4-495922.ga4_portfolio`
OPTIONS (
  location    = "US",
  description = "Modèle en étoile du portfolio GA4"
);


-- ---------------------------------------------------------------------
-- 1. dim_date
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW `projet-ga4-495922.ga4_portfolio.vw_dim_date` AS
SELECT
  date                                                AS date_key,
  EXTRACT(YEAR    FROM date)                          AS year,
  EXTRACT(QUARTER FROM date)                          AS quarter,
  CONCAT('Q', EXTRACT(QUARTER FROM date), ' ',
              EXTRACT(YEAR    FROM date))             AS quarter_label,
  EXTRACT(MONTH   FROM date)                          AS month,
  FORMAT_DATE('%B', date)                             AS month_name,
  FORMAT_DATE('%Y-%m', date)                          AS year_month,
  EXTRACT(WEEK    FROM date)                          AS week,
  CONCAT('S', LPAD(CAST(EXTRACT(WEEK FROM date) AS STRING), 2, '0'), ' ',
              EXTRACT(YEAR FROM date))                AS week_label,
  EXTRACT(DAY       FROM date)                        AS day,
  EXTRACT(DAYOFWEEK FROM date)                        AS day_of_week,
  FORMAT_DATE('%A', date)                             AS day_name,
  EXTRACT(DAYOFWEEK FROM date) IN (1, 7)              AS is_weekend,
  -- Périodes commerciales identifiées sur la plage du dataset
  CASE
    WHEN date BETWEEN DATE '2020-11-26' AND DATE '2020-11-30' THEN 'Black Friday Weekend'
    WHEN date BETWEEN DATE '2020-12-21' AND DATE '2020-12-26' THEN 'Christmas Period'
    WHEN date BETWEEN DATE '2020-12-31' AND DATE '2021-01-02' THEN 'New Year'
    ELSE 'Regular'
  END                                                  AS event_period
FROM UNNEST(GENERATE_DATE_ARRAY('2020-10-01', '2021-02-28')) AS date;


-- ---------------------------------------------------------------------
-- 2. fact_events
-- Grain : 1 ligne = 1 event GA4. On aplatit ici les event_params les
-- plus utiles côté analyse (page, session, engagement, scroll, search,
-- entrance) + device et geo. Attribution user-level conservée telle quelle.
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW `projet-ga4-495922.ga4_portfolio.vw_fact_events` AS
SELECT
  -- Clés
  CONCAT(user_pseudo_id, '-', CAST(event_timestamp AS STRING))          AS event_id,
  user_pseudo_id                                                        AS user_key,
  CONCAT(
    user_pseudo_id, '-',
    CAST((SELECT value.int_value FROM UNNEST(event_params)
          WHERE key = 'ga_session_id') AS STRING)
  )                                                                     AS session_key,
  PARSE_DATE('%Y%m%d', event_date)                                      AS date_key,

  -- Attributs de l'event
  event_name,
  TIMESTAMP_MICROS(event_timestamp)                                     AS event_timestamp,

  -- Paramètres communs à tous les events
  (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'page_location')      AS page_location,
  (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'page_title')         AS page_title,
  (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'page_referrer')      AS page_referrer,
  (SELECT value.int_value    FROM UNNEST(event_params) WHERE key = 'ga_session_id')      AS ga_session_id,
  (SELECT value.int_value    FROM UNNEST(event_params) WHERE key = 'ga_session_number')  AS ga_session_number,
  COALESCE(
    (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'engagement_time_msec'),
    0
  )                                                                                      AS engagement_time_msec,
  CASE WHEN (SELECT value.int_value FROM UNNEST(event_params)
             WHERE key = 'engaged_session_event') = 1
       THEN 1 ELSE 0 END                                                                 AS is_engaged_event,

  -- Paramètres spécifiques à certains events
  (SELECT value.int_value    FROM UNNEST(event_params) WHERE key = 'percent_scrolled')   AS percent_scrolled,
  (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'search_term')        AS search_term,
  (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'link_url')           AS link_url,
  (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'link_domain')        AS link_domain,
  CASE WHEN (SELECT value.string_value FROM UNNEST(event_params)
             WHERE key = 'entrances') = '1'
       THEN 1 ELSE 0 END                                                                 AS is_entrance,

  -- Device (aplati directement pour éviter une dim_device peu utile)
  device.category          AS device_category,
  device.operating_system  AS operating_system,
  device.web_info.browser  AS browser,
  device.language          AS device_language,

  -- Geo (idem, aplati à la source)
  geo.continent,
  geo.country,
  geo.region,
  geo.city,

  -- Attribution user-level (first-touch, telle que fournie par GA4)
  traffic_source.source    AS user_first_source,
  traffic_source.medium    AS user_first_medium,
  traffic_source.name      AS user_first_campaign
FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`;


-- ---------------------------------------------------------------------
-- 3. dim_user
-- Grain : 1 ligne = 1 user_pseudo_id.
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW `projet-ga4-495922.ga4_portfolio.vw_dim_user` AS
WITH user_base AS (
  SELECT
    user_pseudo_id,
    event_date,
    event_name,
    event_timestamp,
    (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS session_id,
    traffic_source.source   AS first_source,
    traffic_source.medium   AS first_medium,
    traffic_source.name     AS first_campaign,
    device.category         AS device_category,
    geo.country
  FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
)
SELECT
  user_pseudo_id                                  AS user_key,
  MIN(PARSE_DATE('%Y%m%d', event_date))           AS first_seen_date,
  MAX(PARSE_DATE('%Y%m%d', event_date))           AS last_seen_date,
  DATE_DIFF(
    MAX(PARSE_DATE('%Y%m%d', event_date)),
    MIN(PARSE_DATE('%Y%m%d', event_date)),
    DAY
  )                                                AS lifespan_days,

  -- First-touch reconstruit : on prend la 1re valeur non nulle dans l'ordre temporel
  ARRAY_AGG(first_source     IGNORE NULLS ORDER BY event_timestamp LIMIT 1)[SAFE_OFFSET(0)] AS user_first_source,
  ARRAY_AGG(first_medium     IGNORE NULLS ORDER BY event_timestamp LIMIT 1)[SAFE_OFFSET(0)] AS user_first_medium,
  ARRAY_AGG(first_campaign   IGNORE NULLS ORDER BY event_timestamp LIMIT 1)[SAFE_OFFSET(0)] AS user_first_campaign,
  ARRAY_AGG(device_category  IGNORE NULLS ORDER BY event_timestamp LIMIT 1)[SAFE_OFFSET(0)] AS first_device_category,
  ARRAY_AGG(country          IGNORE NULLS ORDER BY event_timestamp LIMIT 1)[SAFE_OFFSET(0)] AS first_country,

  COUNT(DISTINCT session_id)                       AS total_sessions,
  COUNTIF(event_name = 'purchase')                 AS total_purchases,

  -- Segmentation simple par fréquence d'achat (à raffiner plus tard si besoin)
  CASE
    WHEN COUNTIF(event_name = 'purchase') = 0               THEN 'Prospect'
    WHEN COUNTIF(event_name = 'purchase') = 1               THEN 'One-time buyer'
    WHEN COUNTIF(event_name = 'purchase') BETWEEN 2 AND 5   THEN 'Regular buyer'
    ELSE                                                          'VIP'
  END                                              AS user_segment
FROM user_base
WHERE user_pseudo_id IS NOT NULL
GROUP BY user_pseudo_id;


-- ---------------------------------------------------------------------
-- 4. dim_session
-- Grain : 1 ligne = 1 session (user_pseudo_id + ga_session_id).
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW `projet-ga4-495922.ga4_portfolio.vw_dim_session` AS
WITH session_events AS (
  SELECT
    user_pseudo_id,
    (SELECT value.int_value    FROM UNNEST(event_params) WHERE key = 'ga_session_id')          AS ga_session_id,
    (SELECT value.int_value    FROM UNNEST(event_params) WHERE key = 'ga_session_number')      AS session_number,
    event_timestamp,
    event_name,
    PARSE_DATE('%Y%m%d', event_date)                                                            AS event_date,
    (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'source')                 AS event_source,
    (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'medium')                 AS event_medium,
    (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'campaign')               AS event_campaign,
    (SELECT value.int_value    FROM UNNEST(event_params) WHERE key = 'engaged_session_event')  AS engaged_event,
    device.category                                                                             AS device_category,
    geo.country
  FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
)
SELECT
  CONCAT(user_pseudo_id, '-', CAST(ga_session_id AS STRING))           AS session_key,
  user_pseudo_id                                                       AS user_key,
  ga_session_id,
  MAX(session_number)                                                  AS session_number,
  MIN(event_date)                                                      AS session_date,

  -- Bornes temporelles + durée
  MIN(TIMESTAMP_MICROS(event_timestamp))                               AS session_start_ts,
  MAX(TIMESTAMP_MICROS(event_timestamp))                               AS session_end_ts,
  TIMESTAMP_DIFF(
    MAX(TIMESTAMP_MICROS(event_timestamp)),
    MIN(TIMESTAMP_MICROS(event_timestamp)),
    SECOND
  )                                                                    AS session_duration_sec,

  -- Compteurs d'events utiles pour le funnel
  COUNT(*)                                       AS events_count,
  COUNTIF(event_name = 'page_view')              AS pageviews,
  COUNTIF(event_name = 'view_item')              AS product_views,
  COUNTIF(event_name = 'add_to_cart')            AS add_to_carts,
  COUNTIF(event_name = 'begin_checkout')         AS checkouts_started,
  COUNTIF(event_name = 'purchase')               AS purchases,

  -- Flags
  CASE WHEN MAX(engaged_event) = 1            THEN 1 ELSE 0 END        AS is_engaged_session,
  CASE WHEN COUNTIF(event_name = 'purchase') > 0 THEN 1 ELSE 0 END     AS is_converting_session,

  -- Attribution session-level, normalisée :
  -- les '<Other>' / '(data deleted)' / NULL sont remappés en '(not set)'
  -- pour aligner avec la convention GA4 et éviter des fragments dans les dashboards.
  CASE
    WHEN ARRAY_AGG(event_source IGNORE NULLS ORDER BY event_timestamp LIMIT 1)[SAFE_OFFSET(0)]
           IN ('<Other>', '(data deleted)')
      OR ARRAY_AGG(event_source IGNORE NULLS ORDER BY event_timestamp LIMIT 1)[SAFE_OFFSET(0)] IS NULL
      THEN '(not set)'
    ELSE ARRAY_AGG(event_source IGNORE NULLS ORDER BY event_timestamp LIMIT 1)[SAFE_OFFSET(0)]
  END                                                                  AS session_source,
  CASE
    WHEN ARRAY_AGG(event_medium IGNORE NULLS ORDER BY event_timestamp LIMIT 1)[SAFE_OFFSET(0)]
           IN ('<Other>', '(data deleted)')
      OR ARRAY_AGG(event_medium IGNORE NULLS ORDER BY event_timestamp LIMIT 1)[SAFE_OFFSET(0)] IS NULL
      THEN '(not set)'
    ELSE ARRAY_AGG(event_medium IGNORE NULLS ORDER BY event_timestamp LIMIT 1)[SAFE_OFFSET(0)]
  END                                                                  AS session_medium,
  CASE
    WHEN ARRAY_AGG(event_campaign IGNORE NULLS ORDER BY event_timestamp LIMIT 1)[SAFE_OFFSET(0)]
           IN ('<Other>', '(data deleted)')
      OR ARRAY_AGG(event_campaign IGNORE NULLS ORDER BY event_timestamp LIMIT 1)[SAFE_OFFSET(0)] IS NULL
      THEN '(not set)'
    ELSE ARRAY_AGG(event_campaign IGNORE NULLS ORDER BY event_timestamp LIMIT 1)[SAFE_OFFSET(0)]
  END                                                                  AS session_campaign,

  ANY_VALUE(device_category)                                           AS device_category,
  ANY_VALUE(country)                                                   AS country

FROM session_events
WHERE ga_session_id IS NOT NULL
GROUP BY user_pseudo_id, ga_session_id;


-- ---------------------------------------------------------------------
-- 5. fact_purchases
-- Grain : 1 ligne = 1 ligne produit dans une transaction.
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW `projet-ga4-495922.ga4_portfolio.vw_fact_purchases` AS
SELECT
  -- Clé technique unique pour une ligne produit
  CONCAT(
    user_pseudo_id, '-',
    CAST(event_timestamp AS STRING), '-',
    COALESCE(item.item_id, 'unknown')
  )                                                                              AS purchase_line_key,
  user_pseudo_id                                                                 AS user_key,
  CONCAT(
    user_pseudo_id, '-',
    CAST((SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS STRING)
  )                                                                              AS session_key,
  PARSE_DATE('%Y%m%d', event_date)                                               AS date_key,
  item.item_id                                                                   AS product_key,

  (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'transaction_id') AS transaction_id,
  TIMESTAMP_MICROS(event_timestamp)                                                   AS purchase_timestamp,

  -- Montants au niveau transaction (attention : répétés sur chaque ligne produit)
  (SELECT value.double_value FROM UNNEST(event_params) WHERE key = 'value')           AS transaction_revenue,
  (SELECT value.double_value FROM UNNEST(event_params) WHERE key = 'tax')             AS transaction_tax,
  (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'currency')        AS currency,
  (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'payment_type')    AS payment_type,
  (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'shipping_tier')   AS shipping_tier,
  (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'coupon')          AS coupon,
  (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'promotion_name')  AS promotion_name,

  -- Ligne produit
  item.item_name                          AS product_name,
  item.item_brand                         AS product_brand,
  item.item_category                      AS product_category,
  item.price                              AS unit_price,
  item.quantity                           AS quantity,
  item.price * item.quantity              AS line_revenue
FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`,
UNNEST(items) AS item
WHERE event_name = 'purchase'
  AND item.item_id IS NOT NULL;


-- ---------------------------------------------------------------------
-- 6. dim_product
-- Grain : 1 ligne = 1 produit (item_id).
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW `projet-ga4-495922.ga4_portfolio.vw_dim_product` AS
WITH product_events AS (
  SELECT
    item.item_id,
    NULLIF(NULLIF(item.item_name,      '(not set)'), '') AS item_name,
    NULLIF(NULLIF(item.item_brand,     '(not set)'), '') AS item_brand,
    NULLIF(NULLIF(item.item_category,  '(not set)'), '') AS item_category,
    NULLIF(NULLIF(item.item_category2, '(not set)'), '') AS item_category2,
    NULLIF(NULLIF(item.item_variant,   '(not set)'), '') AS item_variant,
    item.price,
    event_name,
    event_timestamp
  FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`,
  UNNEST(items) AS item
  WHERE item.item_id IS NOT NULL
    AND item.item_id != '(not set)'
    AND item.item_id != ''
),

-- Vote majoritaire par attribut (un CTE par champ pour rester lisible)
product_names AS (
  SELECT item_id, item_name AS product_name
  FROM (
    SELECT item_id, item_name,
           ROW_NUMBER() OVER (PARTITION BY item_id ORDER BY COUNT(*) DESC) AS rn
    FROM product_events
    WHERE item_name IS NOT NULL
    GROUP BY item_id, item_name
  )
  WHERE rn = 1
),
product_brands AS (
  SELECT item_id, item_brand AS product_brand
  FROM (
    SELECT item_id, item_brand,
           ROW_NUMBER() OVER (PARTITION BY item_id ORDER BY COUNT(*) DESC) AS rn
    FROM product_events
    WHERE item_brand IS NOT NULL
    GROUP BY item_id, item_brand
  )
  WHERE rn = 1
),
product_categories AS (
  SELECT item_id, item_category AS product_category
  FROM (
    SELECT item_id, item_category,
           ROW_NUMBER() OVER (PARTITION BY item_id ORDER BY COUNT(*) DESC) AS rn
    FROM product_events
    WHERE item_category IS NOT NULL
    GROUP BY item_id, item_category
  )
  WHERE rn = 1
),
product_subcategories AS (
  SELECT item_id, item_category2 AS product_subcategory
  FROM (
    SELECT item_id, item_category2,
           ROW_NUMBER() OVER (PARTITION BY item_id ORDER BY COUNT(*) DESC) AS rn
    FROM product_events
    WHERE item_category2 IS NOT NULL
    GROUP BY item_id, item_category2
  )
  WHERE rn = 1
),

-- Métriques agrégées sur la durée du dataset
product_metrics AS (
  SELECT
    item_id,
    AVG(price)                              AS avg_price,
    MIN(price)                              AS min_price,
    MAX(price)                              AS max_price,
    COUNTIF(event_name = 'view_item')       AS total_views,
    COUNTIF(event_name = 'add_to_cart')     AS total_adds_to_cart,
    COUNTIF(event_name = 'purchase')        AS total_purchases,
    COUNT(DISTINCT item_variant)            AS nb_variants_tracked
  FROM product_events
  GROUP BY item_id
)

SELECT
  n.item_id                                       AS product_key,
  n.product_name,
  COALESCE(b.product_brand,        'Unknown')     AS product_brand,
  COALESCE(c.product_category,     'Uncategorized') AS product_category,
  COALESCE(sc.product_subcategory, 'Uncategorized') AS product_subcategory,

  m.avg_price,
  m.min_price,
  m.max_price,
  m.total_views,
  m.total_adds_to_cart,
  m.total_purchases,
  m.nb_variants_tracked,

  -- Statut de fiabilité du tracking funnel (utile pour filtrer les KPIs)
  CASE
    WHEN m.total_views = 0 AND m.total_purchases > 0  THEN 'Purchased only'
    WHEN m.total_views > 0 AND m.total_purchases = 0  THEN 'Viewed only'
    WHEN m.total_views > 0 AND m.total_purchases > 0  THEN 'Full funnel'
    ELSE                                                    'Other'
  END                                              AS tracking_status,

  -- Taux de conversion vue -> achat, calculé seulement quand il est cohérent
  -- (purchases <= views). Sinon NULL pour ne pas polluer les agrégats.
  CASE
    WHEN m.total_views > 0 AND m.total_purchases <= m.total_views
      THEN SAFE_DIVIDE(m.total_purchases, m.total_views)
    ELSE NULL
  END                                              AS view_to_purchase_rate

FROM product_names n
LEFT JOIN product_brands        b  USING (item_id)
LEFT JOIN product_categories    c  USING (item_id)
LEFT JOIN product_subcategories sc USING (item_id)
LEFT JOIN product_metrics       m  USING (item_id)
WHERE n.product_name IS NOT NULL;


-- ---------------------------------------------------------------------
-- 7. fact_sessions_funnel
-- Vue dérivée de dim_session : 1 ligne par session avec les étapes du
-- funnel sous forme de flags + l'étape max atteinte (utile pour un
-- entonnoir Power BI / Looker Studio sans recalcul).
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW `projet-ga4-495922.ga4_portfolio.vw_fact_sessions_funnel` AS
SELECT
  session_key,
  user_key,
  session_date,
  session_source,
  session_medium,
  session_campaign,
  device_category,
  country,

  -- Flags d'étape (utiles pour des taux étape par étape)
  CASE WHEN product_views      > 0 THEN 1 ELSE 0 END AS step_viewed_product,
  CASE WHEN add_to_carts       > 0 THEN 1 ELSE 0 END AS step_added_to_cart,
  CASE WHEN checkouts_started  > 0 THEN 1 ELSE 0 END AS step_started_checkout,
  CASE WHEN purchases          > 0 THEN 1 ELSE 0 END AS step_purchased,

  -- Étape maximale atteinte dans la session
  CASE
    WHEN purchases         > 0 THEN '5_purchased'
    WHEN checkouts_started > 0 THEN '4_started_checkout'
    WHEN add_to_carts      > 0 THEN '3_added_to_cart'
    WHEN product_views     > 0 THEN '2_viewed_product'
    ELSE                            '1_browsed'
  END                                            AS funnel_max_step
FROM `projet-ga4-495922.ga4_portfolio.vw_dim_session`;


-- ---------------------------------------------------------------------
-- 8. Nettoyage
-- Anciennes vues geo/device fusionnées dans fact_events (à supprimer
-- après la première exécution si elles existent encore).
-- ---------------------------------------------------------------------
DROP VIEW IF EXISTS `projet-ga4-495922.ga4_portfolio.vw_dim_geo`;
DROP VIEW IF EXISTS `projet-ga4-495922.ga4_portfolio.vw_dim_device`;
