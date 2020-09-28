-- Aggregate ConnectingNodes into multipoint geometries by grouping them according to the RoadLink which they reference.
--
-- Table: osmm_highways_route.collect_connectingnode
DROP TABLE IF EXISTS osmm_highways_route.collect_connectingnode;

CREATE TABLE osmm_highways_route.collect_connectingnode AS
  SELECT
    roadlink,
    ST_Multi(ST_Collect(foo.geom)) AS geom
  FROM (
    SELECT
      roadlink,
      (ST_Dump(geom)).geom AS geom
    FROM osmm_highways.connectingnode
    WHERE roadlink <> ''
  ) AS foo
  GROUP BY roadlink;

-- Use the multipoint geometries to split the referenced RoadLinks into segments wherever there is an intersection.
--
-- Table: osmm_highways_route.split_roadlink
DROP TABLE IF EXISTS osmm_highways_route.split_roadlink;

CREATE TABLE osmm_highways_route.split_roadlink AS
  SELECT foo.fid, n, 'RoadLink' AS type, foo.routehierarchy, foo.formofway, ST_GeometryN(foo.geom, n) AS geom
  FROM (
    SELECT
      a.id AS fid,
      a.routehierarchy,
      a.formofway,
      (ST_Split(a.geom, b.geom)) AS geom
    FROM 
      osmm_highways.roadlink a,
      osmm_highways_route.collect_connectingnode b 
    WHERE a.id = roadlink
  ) AS foo
  CROSS JOIN generate_series(1, 100) n
  WHERE n <= ST_NumGeometries(foo.geom);

-- Create a table containing the RoadLinks which have not been split.
--
-- Table: osmm_highways_route.non_split_roadlink
DROP TABLE IF EXISTS osmm_highways_route.non_split_roadlink;

CREATE TABLE osmm_highways_route.non_split_roadlink AS
  SELECT id AS fid, 1 AS n, 'RoadLink' AS type, routehierarchy, formofway, geom
  FROM osmm_highways.roadlink a
  WHERE NOT EXISTS (
    SELECT *
    FROM osmm_highways_route.split_roadlink b
    WHERE a.id = b.fid
  );

-- Append split + non-split RoadLinks; PathLinks; and ConnectingLinks into a single table.
--
-- Table: osmm_highways_route.network_geom
DROP TABLE IF EXISTS osmm_highways_route.network_geom;

CREATE TABLE osmm_highways_route.network_geom AS
  SELECT * FROM osmm_highways_route.non_split_roadlink;

INSERT INTO osmm_highways_route.network_geom (fid, n, type, routehierarchy, formofway, geom)
SELECT fid, n, type, routehierarchy, formofway, geom
FROM osmm_highways_route.split_roadlink;

INSERT INTO osmm_highways_route.network_geom (fid, n, type, routehierarchy, formofway, geom)
SELECT id, 1, 'PathLink', '', formofway, geom
FROM osmm_highways.pathlink;

INSERT INTO osmm_highways_route.network_geom (fid, n, type, routehierarchy, formofway, geom)
SELECT id, 1, 'ConnectingLink', '', '', geom
FROM osmm_highways.connectinglink;

-- Generate node lookup using the distinct start- and end-point geometries from the appended table.
--
-- Table: osmm_highways_route.node_table
DROP TABLE IF EXISTS osmm_highways_route.node_table;

CREATE TABLE osmm_highways_route.node_table AS
  SELECT row_number() OVER (ORDER BY foo.p) AS id,
         ST_GeomFromText(foo.p, 27700) AS geom
  FROM (
    SELECT DISTINCT ST_AsText(ST_StartPoint(geom)) AS p FROM osmm_highways_route.network_geom a
    UNION
    SELECT DISTINCT ST_AsText(ST_EndPoint(geom)) AS p FROM osmm_highways_route.network_geom a
  ) foo
  GROUP BY foo.p;

CREATE UNIQUE INDEX node_table_id_idx ON osmm_highways_route.node_table (id);

CREATE INDEX node_table_geom_idx
  ON osmm_highways_route.node_table
  USING gist
  (geom);

-- Create directed graph (edge table) which can be used for routing.
--
-- Table: osmm_highways_route.edge_table
DROP TABLE IF EXISTS osmm_highways_route.edge_table;

CREATE TABLE osmm_highways_route.edge_table AS
  SELECT row_number() OVER (ORDER BY a.fid) AS id,
         a.type,
         a.routehierarchy,
         a.formofway,
         b.id AS source,
         c.id AS target,
         ST_Length(a.geom) AS cost,
         ST_Length(a.geom) AS reverse_cost,
         ST_X(ST_StartPoint(a.geom)) AS x1,
         ST_Y(ST_StartPoint(a.geom)) AS y1,
         ST_X(ST_EndPoint(a.geom)) AS x2,
         ST_Y(ST_EndPoint(a.geom)) AS y2,
         a.geom AS geom
  FROM osmm_highways_route.network_geom a
    JOIN osmm_highways_route.node_table AS b ON ST_AsText(ST_StartPoint(a.geom)) = ST_AsText(b.geom)
    JOIN osmm_highways_route.node_table AS c ON ST_AsText(ST_EndPoint(a.geom)) = ST_AsText(c.geom);

CREATE UNIQUE INDEX edge_table_id_idx ON osmm_highways_route.edge_table (id);
CREATE INDEX edge_table_source_idx ON osmm_highways_route.edge_table (source);
CREATE INDEX edge_table_target_idx ON osmm_highways_route.edge_table (target);

CREATE INDEX edge_table_routehierarchy_idx ON osmm_highways_route.edge_table (routehierarchy);

CREATE INDEX edge_table_geom_idx
  ON osmm_highways_route.edge_table
  USING gist
  (geom);

-- [OPTIONAL] Delete tables which are no longer required.
DROP TABLE osmm_highways_route.collect_connectingnode;
DROP TABLE osmm_highways_route.split_roadlink;
DROP TABLE osmm_highways_route.non_split_roadlink;
DROP TABLE osmm_highways_route.network_geom;
