WITH fires AS (
  SELECT
    event_time,
    session_id,
    COALESCE(list_filter(attributes_list, lambda x: x.key = 'claude.lane')[1].value.stringValue, 'unknown') AS lane,
    list_filter(attributes_list, lambda x: x.key = 'hook_event')[1].value.stringValue AS hook_event,
    TRY_CAST(COALESCE(
      list_filter(attributes_list, lambda x: x.key = 'total_duration_ms')[1].value.stringValue,
      list_filter(attributes_list, lambda x: x.key = 'total_duration_ms')[1].value.intValue
    ) AS DOUBLE) AS ms
  FROM cc_logs_from(getvariable('src'))
  WHERE event_name = 'hook_execution_complete'
),
valid AS (
  SELECT * FROM fires
  WHERE event_time >= getvariable('since')
    AND ms IS NOT NULL AND hook_event IS NOT NULL AND session_id IS NOT NULL
),
ranked AS (
  SELECT *,
    row_number() OVER (PARTITION BY lane, session_id, hook_event ORDER BY event_time) AS pos,
    count(*) OVER (PARTITION BY lane, session_id, hook_event) AS n
  FROM valid
),
slopes AS (
  SELECT lane, hook_event, session_id, regr_slope(ms, (pos - 1) / (n - 1)) AS slope
  FROM ranked
  WHERE n >= getvariable('min_fires')
  GROUP BY lane, hook_event, session_id
),
dist AS (
  SELECT lane, hook_event, count(*) AS fires, count(DISTINCT session_id) AS sessions,
    quantile_cont(ms, 0.5) AS p50, quantile_cont(ms, 0.95) AS p95
  FROM valid
  GROUP BY lane, hook_event
),
trend AS (
  SELECT lane, hook_event, count(*) AS slope_sessions, median(slope) AS median_slope,
    count(*) FILTER (WHERE slope > 0) AS positive_slope
  FROM slopes
  GROUP BY lane, hook_event
),
result AS (
  SELECT d.lane, d.hook_event, d.fires, d.sessions, round(d.p50)::BIGINT AS p50,
    round(d.p95)::BIGINT AS p95, COALESCE(t.slope_sessions, 0) AS slope_sessions,
    round(t.median_slope)::BIGINT AS median_slope, COALESCE(t.positive_slope, 0) AS positive_slope
  FROM dist d
  LEFT JOIN trend t USING (lane, hook_event)
),
meta AS (
  SELECT strftime(getvariable('since'), '%Y-%m-%d %H:%M:%S') AS since,
    (SELECT strftime(min(event_time), '%Y-%m-%d %H:%M:%S') FROM fires) AS oldest
)
SELECT m.since, m.oldest, r.*
FROM meta m
LEFT JOIN result r ON true
ORDER BY r.lane, r.hook_event;
