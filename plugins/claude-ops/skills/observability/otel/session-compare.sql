-- session-compare.sql: tokens by type and a cost reconciliation for two sessions.
--
-- Loaded after cc-otel.sql (for the cc_metrics_from / cc_logs_from macros) by
-- scripts/session-compare.sh, which sets:
--   metrics_src  path of the hot metrics store ($CC_OTEL_STORE/cc-metrics.json)
--   logs_src     path of the hot logs store ($CC_OTEL_STORE/cc-logs.json)
--   a, b         the two session ids
--
-- Output: tab-separated rows, the first column a tag.
--   temporality  metric, session, aggregationTemporality: any token or cost data point of
--                either session that is not delta. Summing data points is valid for delta only.
--   checked      one row once the temporality check has run
--   tokens       session, model, effort ('none' when absent), input, output, cacheRead,
--                cacheCreation (sums of claude_code.token.usage)
--   cost         session, metric data points, metric_usd (claude_code.cost.usage),
--                events_usd (api_request cost), gap_usd, api_requests, status
--
-- effort and aggregationTemporality are read here, not promoted in cc-otel.sql: a new
-- projected column would change the cold Parquet schema that cc_*_cold() reads.

CREATE OR REPLACE TEMP MACRO attr_json(attrs, k) AS
  to_json(list_filter(attrs, lambda x: x.key = k)[1].value);
-- A numeric attribute arrives as doubleValue, intValue (a quoted int64) or stringValue.
-- Read through JSON: a store with no doubleValue anywhere has no such struct member to bind.
CREATE OR REPLACE TEMP MACRO attr_num(attrs, k) AS TRY_CAST(COALESCE(
  json_extract_string(attr_json(attrs, k), '$.doubleValue'),
  json_extract_string(attr_json(attrs, k), '$.intValue'),
  json_extract_string(attr_json(attrs, k), '$.stringValue')) AS DOUBLE);

CREATE TEMP TABLE points AS
SELECT session_id, metric_name, COALESCE(model, 'unknown') AS model,
  COALESCE(list_filter(attributes_list, lambda x: x.key = 'effort')[1].value.stringValue, 'none') AS effort,
  attr_type, value
FROM cc_metrics_from(getvariable('metrics_src'))
WHERE metric_name IN ('claude_code.token.usage', 'claude_code.cost.usage')
  AND session_id IN (getvariable('a'), getvariable('b'));

WITH metrics AS (
  SELECT unnest(sm.metrics) AS m
  FROM (SELECT unnest(rm.scopeMetrics) AS sm
        FROM (SELECT unnest(resourceMetrics) AS rm
              FROM read_json_auto(getvariable('metrics_src'), format = 'newline_delimited',
                                  maximum_object_size = 33554432, sample_size = -1)))
),
sums AS (
  SELECT m.name AS metric_name, m.sum.dataPoints AS dps,
    COALESCE(json_extract_string(to_json(m.sum), '$.aggregationTemporality'), 'unset') AS temporality
  FROM metrics
  WHERE m.name IN ('claude_code.token.usage', 'claude_code.cost.usage')
),
flagged AS (
  SELECT metric_name, temporality, unnest(dps) AS dp
  FROM sums
  WHERE temporality NOT IN ('1', 'AGGREGATION_TEMPORALITY_DELTA')
)
SELECT DISTINCT 'temporality', metric_name,
  list_filter(dp.attributes, lambda x: x.key = 'session.id')[1].value.stringValue AS session_id, temporality
FROM flagged
WHERE session_id IN (getvariable('a'), getvariable('b'))
-- Printed only when this statement ran: the script refuses a run without it.
UNION ALL SELECT 'checked', 'temporality', NULL, NULL;

SELECT 'tokens', session_id, model, effort,
  round(COALESCE(sum(value) FILTER (WHERE attr_type = 'input'), 0))::BIGINT,
  round(COALESCE(sum(value) FILTER (WHERE attr_type = 'output'), 0))::BIGINT,
  round(COALESCE(sum(value) FILTER (WHERE attr_type = 'cacheRead'), 0))::BIGINT,
  round(COALESCE(sum(value) FILTER (WHERE attr_type = 'cacheCreation'), 0))::BIGINT
FROM points
WHERE metric_name = 'claude_code.token.usage'
GROUP BY session_id, model, effort
ORDER BY session_id = getvariable('b'), model, effort;

WITH ids(ord, session_id) AS (VALUES (1, getvariable('a')), (2, getvariable('b'))),
metric AS (
  SELECT session_id, count(*) AS n,
    COALESCE(sum(value) FILTER (WHERE metric_name = 'claude_code.cost.usage'), 0) AS usd
  FROM points
  GROUP BY session_id
),
events AS (
  -- cost_usd_micros is the exact integer form; cost_usd the rounded double.
  SELECT session_id, count(*) AS n,
    COALESCE(sum(COALESCE(attr_num(attributes_list, 'cost_usd_micros') / 1e6,
                          attr_num(attributes_list, 'cost_usd'))), 0) AS usd
  FROM cc_logs_from(getvariable('logs_src'))
  WHERE event_name = 'api_request' AND session_id IN (getvariable('a'), getvariable('b'))
  GROUP BY session_id
),
joined AS (
  SELECT i.ord, i.session_id, COALESCE(m.n, 0) AS points, COALESCE(m.usd, 0) AS metric_usd,
    COALESCE(e.usd, 0) AS events_usd, COALESCE(e.n, 0) AS api_requests
  FROM ids i
  LEFT JOIN metric m USING (session_id)
  LEFT JOIN events e USING (session_id)
)
-- Tolerance: one micro-USD, the resolution of cost_usd_micros.
SELECT 'cost', session_id, points, metric_usd, events_usd, metric_usd - events_usd, api_requests,
  CASE
    WHEN abs(metric_usd - events_usd) <= 1e-6 THEN 'match'
    WHEN metric_usd > events_usd THEN 'events short'
    ELSE 'events exceed metric'
  END
FROM joined
ORDER BY ord;
