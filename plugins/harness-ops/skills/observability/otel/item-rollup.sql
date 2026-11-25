
WITH metrics AS (
  SELECT unnest(sm.metrics) AS m
  FROM (SELECT unnest(rm.scopeMetrics) AS sm
        FROM (SELECT unnest(resourceMetrics) AS rm
              FROM read_json_auto(getvariable('metrics_src'), format = 'newline_delimited',
                                  maximum_object_size = 33554432, sample_size = -1)))
),
sums AS (
  SELECT m.name AS metric_name,
    COALESCE(json_extract_string(to_json(m.sum), '$.aggregationTemporality'), 'unset') AS temporality
  FROM metrics
  WHERE m.name = 'claude_code.token.usage'
)
SELECT DISTINCT 'temporality', metric_name, temporality
FROM sums
WHERE temporality NOT IN ('1', 'AGGREGATION_TEMPORALITY_DELTA')
UNION ALL SELECT 'checked', 'temporality', NULL;

CREATE TEMP TABLE tok AS
SELECT session_id, ccr_session_id, attr_type, value,
  cc_attr(cc_attr_map(cc_attr_entries(attributes_list)), 'autonomy.work_item.url') AS item_url
FROM cc_metrics_from(getvariable('metrics_src'))
WHERE metric_name = 'claude_code.token.usage';

CREATE TEMP TABLE ev AS
SELECT session_id, ccr_session_id, event_name,
  cc_attr(cc_attr_map(cc_attr_entries(attributes_list)), 'autonomy.work_item.url') AS item_url,
  cc_attr(cc_attr_map(cc_attr_entries(attributes_list)), 'delivery.mode') AS delivery_mode
FROM cc_logs_from(getvariable('logs_src'));

CREATE TEMP TABLE ccr_map AS
SELECT ccr_session_id, min(item_url) AS item_url, count(DISTINCT item_url) AS items
FROM (
  SELECT ccr_session_id, item_url FROM tok
  UNION ALL SELECT ccr_session_id, item_url FROM ev
  UNION ALL SELECT ccr_session_id, item_url FROM file_map
)
WHERE COALESCE(ccr_session_id, '') <> '' AND COALESCE(item_url, '') <> ''
GROUP BY ccr_session_id;

CREATE OR REPLACE MACRO resolved_item(own, mapped, items) AS
  COALESCE(NULLIF(own, ''), CASE WHEN items = 1 THEN mapped END, '');

CREATE TEMP TABLE item_rows AS
WITH t AS (
  SELECT resolved_item(x.item_url, c.item_url, c.items) AS item,
    COALESCE(x.ccr_session_id, '') AS ccr, x.session_id, x.attr_type, x.value
  FROM tok x LEFT JOIN ccr_map c ON c.ccr_session_id = x.ccr_session_id
),
e AS (
  SELECT resolved_item(x.item_url, c.item_url, c.items) AS item,
    COALESCE(x.ccr_session_id, '') AS ccr, x.session_id, x.event_name, x.delivery_mode
  FROM ev x LEFT JOIN ccr_map c ON c.ccr_session_id = x.ccr_session_id
),
tokens AS (
  SELECT item, ccr,
    sum(value) FILTER (WHERE attr_type = 'input') AS input_tokens,
    sum(value) FILTER (WHERE attr_type = 'output') AS output_tokens,
    sum(value) FILTER (WHERE attr_type = 'cacheRead') AS cache_read,
    sum(value) FILTER (WHERE attr_type = 'cacheCreation') AS cache_creation
  FROM t
  GROUP BY item, ccr
),
turns AS (
  SELECT item, ccr, count(*) AS turns
  FROM e
  WHERE event_name = 'user_prompt' AND delivery_mode IS DISTINCT FROM 'mid_turn'
  GROUP BY item, ccr
),
sessions AS (
  SELECT item, ccr, count(DISTINCT session_id) AS sessions
  FROM (SELECT item, ccr, session_id FROM t UNION ALL SELECT item, ccr, session_id FROM e)
  WHERE session_id IS NOT NULL
  GROUP BY item, ccr
),
keys AS (
  SELECT item, ccr FROM tokens UNION SELECT item, ccr FROM turns
)
SELECT 'item' AS tag, y.item AS item_url, y.ccr AS ccr_id, COALESCE(s.sessions, 0) AS sessions,
  COALESCE(u.turns, 0) AS turns,
  round(COALESCE(k.input_tokens, 0))::BIGINT AS input_tokens,
  round(COALESCE(k.output_tokens, 0))::BIGINT AS output_tokens,
  round(COALESCE(k.cache_read, 0))::BIGINT AS cache_read,
  round(COALESCE(k.cache_creation, 0))::BIGINT AS cache_creation
FROM keys y
LEFT JOIN tokens k ON k.item = y.item AND k.ccr = y.ccr
LEFT JOIN turns u ON u.item = y.item AND u.ccr = y.ccr
LEFT JOIN sessions s ON s.item = y.item AND s.ccr = y.ccr;

SELECT * FROM item_rows ORDER BY item_url = '', item_url, ccr_id;

SELECT 'ambiguous', ccr_session_id FROM ccr_map WHERE items > 1 ORDER BY ccr_session_id;

SELECT 'done', count(*) FROM item_rows;
