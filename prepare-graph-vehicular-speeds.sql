-- Create a node lookup using the startNode and endNode references.
--
-- Table: osmm_highways_route.node_table
DROP TABLE IF EXISTS osmm_highways_route.node_table;

CREATE TABLE osmm_highways_route.node_table AS
  SELECT row_number() OVER (ORDER BY foo.p) AS id,
         foo.p AS node,
         foo.geom
  FROM (
    SELECT DISTINCT CONCAT(a.startnode, a.startgradeseparation) AS p, ST_Startpoint(geom) AS geom FROM osmm_highways.roadlink a
    UNION
    SELECT DISTINCT CONCAT(a.endnode, a.endgradeseparation) AS p, ST_Endpoint(geom) AS geom FROM osmm_highways.roadlink a
  ) foo
  GROUP BY foo.p, foo.geom;

CREATE UNIQUE INDEX node_table_id_idx ON osmm_highways_route.node_table (id);
CREATE INDEX node_table_node_idx ON osmm_highways_route.node_table (node);

CREATE INDEX node_table_geom_idx
  ON osmm_highways_route.node_table
  USING gist
  (geom);

-- Create a directed graph which can be used for routing.
-- Uses Basemap average speed data for calculating the fastest route.
--
-- Table: osmm_highways_route.edge_table
DROP TABLE IF EXISTS osmm_highways_route.edge_table;

CREATE TABLE osmm_highways_route.edge_table AS
  SELECT row_number() OVER (ORDER BY a.ogc_fid) AS id,
         a.id AS fid,
         a.roadname AS name,
         a.alternatename AS alt_name,
         a.roadclassificationnumber AS ref,
         a.roadclassification,
         a.routehierarchy,
         a.formofway,
         a.operationalstate,
         a.directionality,
         a.length,
         b.id AS source,
         c.id AS target,
         CASE
           WHEN directionality = 'in opposite direction' THEN -1
           ELSE a.length
         END AS cost_distance,
         CASE
           WHEN directionality = 'in direction' THEN -1
           ELSE a.length
         END AS reverse_cost_distance,
         CASE
           WHEN directionality = 'in opposite direction' THEN -1
           ELSE ((a.length / 1000) / (COALESCE(d.peakam0709monfria + 0.01, 48)) * 60)
         END AS cost_time_peakam0709monfri,
         CASE
           WHEN directionality = 'in direction' THEN -1
           WHEN directionality = 'in opposite direction' THEN ((a.length / 1000) / (COALESCE(d.peakam0709monfria + 0.01, 48)) * 60)
           ELSE ((a.length / 1000) / (COALESCE(d.peakam0709monfrib + 0.01, 48)) * 60)
         END AS reverse_cost_time_peakam0709monfri,
         CASE
           WHEN directionality = 'in opposite direction' THEN -1
           ELSE ((a.length / 1000) / (COALESCE(d.peakpm1619monfria + 0.01, 48)) * 60)
         END AS cost_time_peakpm1619monfri,
         CASE
           WHEN directionality = 'in direction' THEN -1
           WHEN directionality = 'in opposite direction' THEN ((a.length / 1000) / (COALESCE(d.peakpm1619monfria + 0.01, 48)) * 60)
           ELSE ((a.length / 1000) / (COALESCE(d.peakpm1619monfrib + 0.01, 48)) * 60)
         END AS reverse_cost_time_peakpm1619monfri,
         CASE
           WHEN directionality = 'in opposite direction' THEN -1
           ELSE ((a.length / 1000) / (COALESCE(d.offpeak1016monfria + 0.01, 48)) * 60)
         END AS cost_time_offpeak1016monfri,
         CASE
           WHEN directionality = 'in direction' THEN -1
           WHEN directionality = 'in opposite direction' THEN ((a.length / 1000) / (COALESCE(d.offpeak1016monfria + 0.01, 48)) * 60)
           ELSE ((a.length / 1000) / (COALESCE(d.offpeak1016monfrib + 0.01, 48)) * 60)
         END AS reverse_cost_time_offpeak1016monfri,
         CASE
           WHEN directionality = 'in opposite direction' THEN -1
           ELSE ((a.length / 1000) / (COALESCE(d.eveningspeed1923everydaya + 0.01, 48)) * 60)
         END AS cost_time_eveningspeed1923everyday,
         CASE
           WHEN directionality = 'in direction' THEN -1
           WHEN directionality = 'in opposite direction' THEN ((a.length / 1000) / (COALESCE(d.eveningspeed1923everydaya + 0.01, 48)) * 60)
           ELSE ((a.length / 1000) / (COALESCE(d.eveningspeed1923everydayb + 0.01, 48)) * 60)
         END AS reverse_cost_time_eveningspeed1923everyday,
         CASE
           WHEN directionality = 'in opposite direction' THEN -1
           ELSE ((a.length / 1000) / (COALESCE(d.nighttime0004everydaya + 0.01, 48)) * 60)
         END AS cost_time_nighttime0004everyday,
         CASE
           WHEN directionality = 'in direction' THEN -1
           WHEN directionality = 'in opposite direction' THEN ((a.length / 1000) / (COALESCE(d.nighttime0004everydaya + 0.01, 48)) * 60)
           ELSE ((a.length / 1000) / (COALESCE(d.nighttime0004everydayb + 0.01, 48)) * 60)
         END AS reverse_cost_time_nighttime0004everyday,
         CASE
           WHEN directionality = 'in opposite direction' THEN -1
           ELSE ((a.length / 1000) / (COALESCE(d.weekend0719a + 0.01, 48)) * 60)
         END AS cost_time_weekend0719,
         CASE
           WHEN directionality = 'in direction' THEN -1
           WHEN directionality = 'in opposite direction' THEN ((a.length / 1000) / (COALESCE(d.weekend0719a + 0.01, 48)) * 60)
           ELSE ((a.length / 1000) / (COALESCE(d.weekend0719b + 0.01, 48)) * 60)
         END AS reverse_cost_time_weekend0719,
         ST_X(ST_StartPoint(a.geom)) AS x1,
         ST_Y(ST_StartPoint(a.geom)) AS y1,
         ST_X(ST_EndPoint(a.geom)) AS x2,
         ST_Y(ST_EndPoint(a.geom)) AS y2,
         a.geom
  FROM osmm_highways.roadlink a
    JOIN osmm_highways_route.node_table AS b ON CONCAT(a.startnode, a.startgradeseparation) = b.node
    JOIN osmm_highways_route.node_table AS c ON CONCAT(a.endnode, a.endgradeseparation) = c.node
    LEFT OUTER JOIN osmm_highways_speeds.average_speeds AS d ON a.id = d.roadlinkid;

CREATE UNIQUE INDEX edge_table_id_idx ON osmm_highways_route.edge_table (id);
CREATE INDEX edge_table_source_idx ON osmm_highways_route.edge_table (source);
CREATE INDEX edge_table_target_idx ON osmm_highways_route.edge_table (target);

CREATE INDEX edge_table_routehierarchy_idx ON osmm_highways_route.edge_table (routehierarchy);
CREATE INDEX edge_table_operationalstate_idx ON osmm_highways_route.edge_table (operationalstate);

CREATE INDEX edge_table_geom_idx
  ON osmm_highways_route.edge_table
  USING gist
  (geom);

-- [OPTIONAL] Add vehicular ferry routes to the directed graph. 
--
-- Table: osmm_highways_route.ferryterminal
CREATE TABLE osmm_highways_route.ferryterminal AS
SELECT id,
       array_agg(identifier) AS element_href
FROM osmm_highways.ferryterminal_element
WHERE id IN (SELECT id FROM osmm_highways.ferryterminal_element WHERE role = 'RoadNode')
GROUP BY id;

INSERT INTO osmm_highways_route.edge_table
  SELECT row_number() OVER (ORDER BY a.ogc_fid) + 6000000 AS id,
  a.id AS fid,
  array[]::text[] AS name,
  array[]::text[] AS alt_name,
  '' AS ref,
  '' AS roadclassification,
  'Ferry Route' AS routehierarchy,
  '' AS formofway,
  'Open' AS operationalstate,
  'both directions' AS directionality,
  ST_Length(a.geom) AS length,
  (SELECT id FROM osmm_highways_route.node_table WHERE node = CONCAT(b.element_href[2], 0)) AS source,
  (SELECT id FROM osmm_highways_route.node_table WHERE node = CONCAT(c.element_href[2], 0)) AS target,
  ROUND(ST_Length(a.geom)::numeric, 2) AS cost_distance,
  ROUND(ST_Length(a.geom)::numeric, 2) AS reverse_cost_distance,
  1 AS cost_time_peakam0709monfri,
  1 AS reverse_cost_time_peakam0709monfri,
  1 AS cost_time_peakpm1619monfri,
  1 AS reverse_cost_time_peakpm1619monfri,
  1 AS cost_time_offpeak1016monfri,
  1 AS reverse_cost_time_offpeak1016monfri,
  1 AS cost_time_eveningspeed1923everyday,
  1 AS reverse_cost_time_eveningspeed1923everyday,
  1 AS cost_time_nighttime0004everyday,
  1 AS reverse_cost_time_nighttime0004everyday,
  1 AS cost_time_weekend0719,
  1 AS reverse_cost_time_weekend0719,
  ST_X(ST_StartPoint(a.geom)) AS x1,
  ST_Y(ST_StartPoint(a.geom)) AS y1,
  ST_X(ST_EndPoint(a.geom)) AS x2,
  ST_Y(ST_EndPoint(a.geom)) AS y2,
  a.geom
  FROM osmm_highways.ferrylink a
    JOIN osmm_highways_route.ferryterminal AS b ON a.startnode = b.element_href[1]
    JOIN osmm_highways_route.ferryterminal AS c ON a.endnode = c.element_href[1];

REINDEX TABLE osmm_highways_route.edge_table

DROP TABLE osmm_highways_route.ferryterminal;
