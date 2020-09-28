# Routing analysis using OS MasterMap Highways Network and pgRouting

## Introduction

The [pgRouting](https://pgrouting.org/) project extends the PostGIS/PostgreSQL geospatial database to provide geospatial routing functionality.

In its simplest form - the routing functionality will be a directed graph which allows for the shortest path (in terms of distance) to be calculated/returned. 

## Prerequisites

Assumes Highways data has been translated from its native GML format using [osmm-highways-network-translator](https://github.com/tmnnrs/osmm-highways-network-translator).

## Analysis

The following SQL scripts output data for use in routing applications.

- [prepare-graph-vehicular-basic.sql](prepare-graph-vehicular-basic.sql)
  - Generates a basic routable network for calculating the best vehicular route using the OS MasterMap Highways Network Road product.
- [prepare-graph-vehicular-speeds.sql](prepare-graph-vehicular-speeds.sql)
  - Generates a routable network for calculating the best vehicular route at a given time period using the OS MasterMap Highways Network with Routing and Asset Management Information and Average Speed.
- [prepare-graph-pedestrian-basic.sql](prepare-graph-pedestrian-basic.sql)
  - Generates a routable network for pedestrians by integrating the OS MasterMap Highways Network Road and Path products.

Each of the script will ultimately output two tables: a node lookup (called **node_table**) and a directed graph (called **edge_table**). Both use the RoadLink tables as their source.

The node lookup is generated using the startNode and endNode references. Where appropriate, it introduces additional nodes using the grade separation to ensure the real-world physical separations between RoadLinks are handled accordingly.

The directed graph is used for the routing analysis. It utilises the node lookup to generate the required `'source'` and `'target'` integer fields; along with adding `'cost'` and `'reverse_cost'` fields for one ways (the wrong way has a negative cost).

## Demo

The included HTML documents can be run on a local web server (running PHP) as a means to demonstrate the routable network via an interactive map.

The **shortest-path** examples allow users to drag the start/destination points around; and [optionally] selecting the type of route (shortest vs fastest).

The **service-area** examples allow users to drag the origin point around; as well as choosing the drive-time and output type: alpha shape (polygon) or driving distance (line).
