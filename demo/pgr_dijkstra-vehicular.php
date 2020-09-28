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

  $geojson = array(
    'type' => 'FeatureCollection',
    'features' => array(),
    'metadata' => array(
      'source' => null,
      'source_geom' => '',
      'target' => null,
      'target_geom' => '',
      'time' => 'N/A',
      'distance' => 0
    )
  );

  $option = 'distance';
  if( isset($_GET["option"]) ) {
    $option = $_GET["option"];
  }

  $period = '';
  if( isset($_GET["period"]) && $option == 'time' ) {
    $period = '_' . $_GET["period"];
  }

  $points = $_GET["points"];
  $points = explode(',', $points);

  $counter = 0;
  foreach ($points as &$point) {
    $point = str_replace(' ', ',', $point);

    $sql = "SELECT id, ST_AsText(geom) AS geom
            FROM osmm_highways_route.node_table
            ORDER BY geom <-> ST_Transform(ST_SetSRID(ST_MakePoint($point), 4326), 27700)
            LIMIT 1";

    $result = pg_query($dbcon, $sql);

    while($row = pg_fetch_assoc($result)) {
      $node = $row['id'];
      $geom = $row['geom'];
    }

    if( $counter == 0 ) {
      $geojson['metadata']['source'] = $node;
      $geojson['metadata']['source_geom'] = $geom;
    }
    else if ($counter == 1) {
      $geojson['metadata']['target'] = $node;
      $geojson['metadata']['target_geom'] = $geom;
    }

    $counter++;
  }

  $source = $geojson['metadata']['source'];
  $target = $geojson['metadata']['target'];

  $g1 = $geojson['metadata']['source_geom'];
  $g2 = $geojson['metadata']['target_geom'];

  $sql = "SELECT a.*, b.length, ST_AsGeoJSON(ST_Transform(b.geom, 4326), 7) AS geom
          FROM pgr_dijkstra(
            'SELECT id, source, target, cost_$option$period AS cost, reverse_cost_$option$period AS reverse_cost
             FROM osmm_highways_route.edge_table
             WHERE geom && ST_Buffer(ST_Envelope(ST_Collect(ST_GeomFromText(''$g1''), ST_GeomFromText(''$g2''))), 20000)',
            $source, $target
          ) AS a
          LEFT JOIN osmm_highways_route.edge_table AS b
          ON (a.edge = b.id) ORDER BY seq";

  $result = pg_query($dbcon, $sql);

  $_cost = 0;
  $_length = 0;

  while($row = pg_fetch_assoc($result)) {
    $cost = round($row['cost'], 5);
    $length = $row['length'];

    $geometry = json_decode($row['geom'], true);

    if( isset($geometry) ) {
      $feature = array(
        'type' => 'Feature',
        'properties' => array('cost' => $cost, 'length' => $length),
        'geometry' => $geometry
      );

      $_cost += $cost;
      $_length += $length;

      array_push($geojson['features'], $feature);
    }
  }

  if( $option != 'distance' ) {
    $geojson['metadata']['time'] = gmdate('H:i:s', floor($_cost * 60));
  }

  $geojson['metadata']['distance'] = round($_length, 2);

  unset($geojson['metadata']['source_geom']);
  unset($geojson['metadata']['target_geom']);

  echo json_encode($geojson, JSON_NUMERIC_CHECK);

  pg_close($dbcon);

?>
