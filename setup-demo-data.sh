#!/bin/bash

help() {
   echo 'usage: setup-demo-data.sh [--host=HOST]'
   echo '                          [--port=PORT]'
   echo '                          [--username=USERNAME]'
   echo '                          [--password=PASSWORD]'
   echo '                          [--grants-are-setup-externally]'
   echo '                          [--dbname=DBNAME]'
   echo '       setup-demo-data.sh [--pgservice_demo_db=PGSERVICE --pgservice_config_db=PGSERVICE] '
   echo '       setup-demo-data.sh --help'
   echo
   exit 1
}

# defaults
#
# they get unexported below if --pgservice is set
#
export PGDATABASE=qwc_demo
export PGUSER=qwc_admin
export PGPASSWORD=qwc_admin
export PGHOST=
export PGPORT=5432
GRANTS_ARE_SETUP_EXTERNALLY=no

USE_PGSERVICE=no

PGSERVICE_DEMO_DB=
PGSERVICE_CONFIG_DB=

# parse option parameters
while [ "$1" != "" ]; do
  [  "$1" == "--help"       ] && help
  [[ "$1" =~ ^--dbname=    ]] && export PGDATABASE=$(  echo "$1" | sed 's/--dbname=//'    )
  [[ "$1" =~ ^--username=  ]] && export PGUSER=$(      echo "$1" | sed 's/--username=//'  )
  [[ "$1" =~ ^--password=  ]] && export PGPASSWORD=$(  echo "$1" | sed 's/--password=//'  )
  [[ "$1" =~ ^--host=      ]] && export PGHOST=$(      echo "$1" | sed 's/--host=//'      )
  [[ "$1" =~ ^--port=      ]] && export PGPORT=$(      echo "$1" | sed 's/--port=//'      )

  [[ "$1" =~ ^--grants-are-setup-externally ]] && GRANTS_ARE_SETUP_EXTERNALLY=yes

  [[ "$1" =~ ^--pgservice_demo_db=   ]] && PGSERVICE_DEMO_DB=$(   echo "$1" | sed 's/--pgservice_demo_db=//'   )
  [[ "$1" =~ ^--pgservice_config_db= ]] && PGSERVICE_CONFIG_DB=$( echo "$1" | sed 's/--pgservice_config_db=//' )
  shift
done

[ "${PGSERVICE_DEMO_DB}${PGSERVICE_CONFIG_DB}" != "" ] && USE_PGSERVICE=yes

if [ "$USE_PGSERVICE" == "yes" ]; then
  [ "$PGSERVICE_DEMO_DB"   == "" ] && echo "please set --pgservice_demo_db"   >&2 && exit 2
  [ "$PGSERVICE_CONFIG_DB" == "" ] && echo "please set --pgservice_config_db" >&2 && exit 2

  export -n PGDATABASE
  export -n PGUSER
  export -n PGPASSWORD
  export -n PGHOST
  export -n PGPORT
fi

set -ex

# import demo data into GeoDB
if [ "$USE_PGSERVICE" == "yes" ]; then

  OGR_PG_CONNECTION="service=$PGSERVICE_DEMO_DB"
  DEMO_DB_CONNECTION="service=$PGSERVICE_DEMO_DB"
  CONFIG_DB_CONNECTION="service=$PGSERVICE_CONFIG_DB"
else # "$USE_PGSERVICE" == "no"

  OGR_PG_CONNECTION="dbname=$PGDATABASE user=$PGUSER password=$PGPASSWORD port=$PGPORT $PGHOST"
  # Use credentials from ENV variables
  DEMO_DB_CONNECTION="$PGDATABASE"
  CONFIG_DB_CONNECTION="$PGDATABASE"
fi

ogr2ogr -f PostgreSQL PG:"$OGR_PG_CONNECTION" \
        -lco SCHEMA=qwc_geodb \
        -lco GEOMETRY_NAME=wkb_geometry \
        -lco OVERWRITE=YES \
        /tmp/demo_geodata.gpkg

# create view for fulltext search
psql -v ON_ERROR_STOP=1 $DEMO_DB_CONNECTION <<-EOSQL
CREATE OR REPLACE VIEW qwc_geodb.search_v AS
    SELECT
        'ne_10m_admin_0_countries'::text AS subclass,
        'Country'::text AS filterword,
        ogc_fid AS id_in_class,
        'ogc_fid' AS id_name,
        'str:n' AS id_type,
        name_long || ' (Country)' AS displaytext,
        name_long || ' ' || iso_a2 AS search_part_1,
        'Country ISO'::text AS search_part_2,
        wkb_geometry AS geom
    FROM qwc_geodb.ne_10m_admin_0_countries
;
EOSQL

# create demo tables and features for editing
psql -v ON_ERROR_STOP=1 $DEMO_DB_CONNECTION <<-EOSQL
    CREATE TABLE qwc_geodb.edit_points
    (
      id serial,
      name character varying(32),
      description text,
      num integer,
      value double precision,
      type smallint,
      amount numeric(5,2),
      validated boolean,
      datetime timestamp without time zone,
      geom geometry(Point,3857),
      CONSTRAINT edit_points_pkey PRIMARY KEY (id)
    );
    CREATE INDEX sidx_edit_points_geom
      ON qwc_geodb.edit_points
      USING gist
      (geom);

    INSERT INTO qwc_geodb.edit_points (name, description, num, value, type, amount, validated, datetime, geom)
      VALUES ('point', 'Example Point', 123, 1.234, 1, 123.45, TRUE, current_timestamp,
        ST_GeomFromText('POINT(950758.0 6003950.0)', 3857));

    CREATE TABLE qwc_geodb.edit_lines
    (
      id serial,
      name character varying(32),
      description text,
      num integer,
      value double precision,
      type smallint,
      amount numeric(5,2),
      validated boolean,
      datetime timestamp without time zone,
      geom geometry(LineString,3857),
      CONSTRAINT edit_lines_pkey PRIMARY KEY (id)
    );
    CREATE INDEX sidx_edit_lines_geom
      ON qwc_geodb.edit_lines
      USING gist
      (geom);

    INSERT INTO qwc_geodb.edit_lines (name, description, num, value, type, amount, validated, datetime, geom)
      VALUES ('line', 'Example Line', 456, 45.6, 1, 456.78, FALSE, current_timestamp,
        ST_GeomFromText('LINESTRING(950922 6003840,950918 6003863,950904 6003868,950904 6003883,950904 6003918)', 3857));

    CREATE TABLE qwc_geodb.edit_polygons
    (
      id serial,
      name character varying(32),
      description text,
      num integer,
      value double precision,
      type smallint,
      amount numeric(5,2),
      validated boolean,
      datetime timestamp without time zone,
      geom geometry(Polygon,3857),
      CONSTRAINT edit_polygons_pkey PRIMARY KEY (id)
    );
    CREATE INDEX sidx_edit_polygons_geom
      ON qwc_geodb.edit_polygons
      USING gist
      (geom);

    INSERT INTO qwc_geodb.edit_polygons (name, description, num, value, type, amount, validated, datetime, geom)
      VALUES ('polygon', 'Example Polygon', 789, 789.0, 1, 789.0, TRUE, current_timestamp,
        ST_GeomFromText('POLYGON((950819 6003952,950831 6003947,950828 6003925,950822 6003905,950804 6003913,950819 6003952))', 3857));
EOSQL

if [ "$GRANTS_ARE_SETUP_EXTERNALLY" == "no" ]; then
  psql -v ON_ERROR_STOP=1 $DEMO_DB_CONNECTION <<-EOSQL
    GRANT SELECT ON ALL TABLES IN SCHEMA qwc_geodb TO qgis_server;
    GRANT SELECT ON ALL SEQUENCES IN SCHEMA qwc_geodb TO qgis_server;
    GRANT SELECT ON ALL TABLES IN SCHEMA qwc_geodb TO qwc_service;
    GRANT SELECT ON ALL SEQUENCES IN SCHEMA qwc_geodb TO qwc_service;
    GRANT ALL ON ALL TABLES IN SCHEMA qwc_geodb TO qwc_service_write;
    GRANT USAGE ON ALL SEQUENCES IN SCHEMA qwc_geodb TO qwc_service_write;
EOSQL
fi

# insert demo records into ConfigDB
# >>> from werkzeug.security import generate_password_hash
# >>> print(generate_password_hash('demo'))
psql -v ON_ERROR_STOP=1 $CONFIG_DB_CONNECTION <<-EOSQL
  -- demo role and user (password: 'demo')
  INSERT INTO qwc_config.roles (name, description)
    VALUES ('demo', 'Demo role');
  INSERT INTO qwc_config.users (name, description, password_hash)
    VALUES('demo', 'Demo user', 'pbkdf2:sha256:50000\$qwQxJa3a\$91e81c06ce49eb76692e69f430e937dc5eac5b2f301eced831d0bd4e0f1e3120');
  INSERT INTO qwc_config.users_roles (user_id, role_id)
    VALUES ((SELECT id FROM qwc_config.users WHERE name = 'demo'), (SELECT id FROM qwc_config.roles WHERE name = 'demo'));

  -- resources for editing
  INSERT INTO qwc_config.resources (parent_id, type, name)
    VALUES (NULL, 'map', 'qwc_demo');
  INSERT INTO qwc_config.resources (parent_id, type, name)
    VALUES ((SELECT id FROM qwc_config.resources WHERE type = 'map' AND name = 'qwc_demo'), 'data', 'edit_points');
  INSERT INTO qwc_config.resources (parent_id, type, name)
    VALUES ((SELECT id FROM qwc_config.resources WHERE type = 'map' AND name = 'qwc_demo'), 'data', 'edit_lines');
  INSERT INTO qwc_config.resources (parent_id, type, name)
    VALUES ((SELECT id FROM qwc_config.resources WHERE type = 'map' AND name = 'qwc_demo'), 'data', 'edit_polygons');

  -- permissions for public editing
  INSERT INTO qwc_config.permissions (role_id, resource_id)
    VALUES ((SELECT id FROM qwc_config.roles WHERE name = 'public'), (SELECT id FROM qwc_config.resources WHERE type = 'map' AND name = 'qwc_demo'));
  INSERT INTO qwc_config.permissions (role_id, resource_id, write)
    VALUES ((SELECT id FROM qwc_config.roles WHERE name = 'public'), (SELECT id FROM qwc_config.resources WHERE type = 'data' AND name = 'edit_points'), TRUE);
  INSERT INTO qwc_config.permissions (role_id, resource_id, write)
    VALUES ((SELECT id FROM qwc_config.roles WHERE name = 'public'), (SELECT id FROM qwc_config.resources WHERE type = 'data' AND name = 'edit_lines'), TRUE);
  INSERT INTO qwc_config.permissions (role_id, resource_id, write)
    VALUES ((SELECT id FROM qwc_config.roles WHERE name = 'public'), (SELECT id FROM qwc_config.resources WHERE type = 'data' AND name = 'edit_polygons'), TRUE);
EOSQL

# add demo user info columns
psql -v ON_ERROR_STOP=1 $CONFIG_DB_CONNECTION <<-EOSQL
  ALTER TABLE qwc_config.user_infos
    ADD COLUMN surname character varying NOT NULL;
  ALTER TABLE qwc_config.user_infos
    ADD COLUMN first_name character varying NOT NULL;
  ALTER TABLE qwc_config.user_infos
    ADD COLUMN street character varying;
  ALTER TABLE qwc_config.user_infos
    ADD COLUMN zip character varying(255);
  ALTER TABLE qwc_config.user_infos
    ADD COLUMN city character varying;
EOSQL

psql -v ON_ERROR_STOP=1 $DEMO_DB_CONNECTION --username "$POSTGRES_USER" <<-EOSQL
  VACUUM FULL;
EOSQL
