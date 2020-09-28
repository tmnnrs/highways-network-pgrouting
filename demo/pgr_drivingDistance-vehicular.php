<?php

  include_once 'config.php';

  header('access-control-allow-origin: *');
  header('access-control-allow-methods: GET, PUT, POST, DELETE, OPTIONS');
  header('access-control-allow-headers: Content-Type, Content-Range, Content-Disposition, Content-Description');
  header('content-type: application/json; charset=utf-8');

  if( version_compare(phpversion(), '7.1', '>=') ) {
    ini_set('serialize_precision', -1);
  }

  $dbcon = pg_connect("dbname=".PG_DB." host=".PG_HOST." port=".PG_PORT." user=".PG_USER." password=".PG_PWRD) or die('connection failed');

  $option = 'alphashape';
  if( isset($_GET["option"]) ) {
    $option = $_GET["option"];
  }

  $cost = 10;
  if( isset($_GET["cost"]) ) {
    $cost = $_GET["cost"];
  }

  $period = 'nighttime0004everyday';
  if( isset($_GET["period"]) ) {
    $period = $_GET["period"];
  }

  $percent = 0.85;

  $geojson = array(
    'type' => 'FeatureCollection',
    'features' => array(),
    'metadata' => array(
      'source' => 0,
      'option' => $option,
      'cost' => $cost
    )
  );

  $point = $_GET["point"];

  $sql = "SELECT id, ST_AsText(geom) AS geom
          FROM osmm_highways_route.node_table
          ORDER BY geom <-> ST_Transform(ST_SetSRID(ST_MakePoint($point), 4326), 27700)
          LIMIT 1";

  $result = pg_query($dbcon, $sql);

  while($row = pg_fetch_assoc($result)) {
    $node = $row['id'];
    $geom = $row['geom'];
  }

  $geojson['metadata']['source'] = $node;

  $radius = (1.86 * $cost) * 1000;

  if( $option == 'alphashape' ) {
    $sql = "SELECT ST_AsGeoJSON(ST_Transform(ST_CollectionExtract(ST_ConcaveHull(ST_Collect(ST_Force2D(geom)), $percent), 3), 4326), 7) AS geom
            FROM (
              SELECT a.*, b.geom FROM pgr_drivingDistance(
                'SELECT id, source, target, 0, cost_time_$period AS cost, reverse_cost_time_$period AS reverse_cost
                 FROM osmm_highways_route.edge_table
                 WHERE routehierarchy <> ''Ferry Route'' AND geom && ST_Buffer(ST_GeomFromText(''$geom''), $radius)',
                array[$node], $cost
              ) AS a
              LEFT JOIN osmm_highways_route.node_table AS b
              ON a.node = b.id
            ) AS c";
  }
  else if( $option == 'drivingdistance' ) {
    $sql = "SELECT a.*, ST_AsGeoJSON(ST_Transform(b.geom, 4326), 7) AS geom
            FROM pgr_drivingDistance(
              'SELECT id, source, target, 0, cost_time_$period AS cost, reverse_cost_time_$period AS reverse_cost
               FROM osmm_highways_route.edge_table
               WHERE routehierarchy <> ''Ferry Route'' AND geom && ST_Buffer(ST_GeomFromText(''$geom''), $radius)',
              array[$node], $cost
            ) AS a
            LEFT JOIN osmm_highways_route.edge_table AS b
            ON a.edge = b.id";
  }

  $result = pg_query($dbcon, $sql);

  while($row = pg_fetch_assoc($result)) {
    $properties = array();
    
    $geometry = json_decode($row['geom'], true);

    if( isset($geometry) ) {
      $feature = array(
        'type' => 'Feature',
        'properties' => $properties,
        'geometry' => $geometry
      );

      array_push($geojson['features'], $feature);
    }
  }

  echo json_encode($geojson, JSON_NUMERIC_CHECK);

  pg_close($dbcon);

?>
