#!/bin/bash

set -e

if [ -z $1 -o -z $2 ] ; then
  echo "usage1: smoke_test_docker_image.sh TYPE[pg|influx] IMAGE_TAG"
  exit 1
fi

if [ $1 != "pg" -a $1 != "influx" ] ; then
  echo "usage: smoke_test_docker_image.sh TYPE[pg|influx] IMAGE_TAG"
  exit 1
fi

METRICDBTYPE=$1
IMAGE=$2
CONTAINER_NAME="smoke_test_$METRICDBTYPE"
WEBUIPORT=$(shuf -i 10000-65000 -n 1)
INFLUXPORT=$(shuf -i 10000-65000 -n 1)
GRAFANAPORT=$(shuf -i 10000-65000 -n 1)
LOCALHOST=127.0.0.1
# these vars are passed to subshell, so export them
export PGHOST=localhost
export PGPORT=$(shuf -i 10000-65000 -n 1)
export PGUSER=pgwatch2
export PGPASSWORD=pgwatch2admin
export PGDATABASE=pgwatch2_metrics

echo "starting smoke test of Postgres image $IMAGE ..."
echo "stopping and removing existing container named $CONTAINER_NAME if any"
docker stop "$CONTAINER_NAME" &>/dev/null && docker rm "$CONTAINER_NAME" &>/dev/null

echo "launching docker container using ports GRAFANA=$GRAFANAPORT, PG=$PGPORT, WEBUI=$WEBUIPORT, INFLUX=$INFLUXPORT..."
DOCKER_RUN=$(docker run -d --rm --cpus=2 -p $LOCALHOST:$WEBUIPORT:8080 -p $LOCALHOST:$GRAFANAPORT:3000 -p $LOCALHOST:$PGPORT:5432 -p $LOCALHOST:$INFLUXPORT:8086 --name "$CONTAINER_NAME" $IMAGE)
echo "OK. container $CONTAINER_NAME started"


echo "sleeping 60s..."
sleep 60


echo "checking Web UI response ..."
curl -s $LOCALHOST:$WEBUIPORT/dbs >/dev/null
echo "OK"


echo "adding new DB 'smoke1' to monitoring via POST to Web UI /dbs page..."
http --verify=no -f POST $LOCALHOST:$WEBUIPORT/dbs md_unique_name=smoke1 md_dbtype=postgres md_hostname=/var/run/postgresql/ md_port=5432 md_dbname=postgres \
  md_user=pgwatch2 md_password=pgwatch2admin md_password_type=plain-text md_preset_config_name=basic md_is_enabled=true new=New >/dev/null
echo "OK"

echo "adding new DB 'smoke2' to monitoring via POST to Web UI /dbs page..."
http --verify=no -f POST $LOCALHOST:$WEBUIPORT/dbs md_unique_name=smoke2 md_dbtype=postgres md_hostname=/var/run/postgresql/ md_port=5432 md_dbname=pgwatch2 \
  md_user=pgwatch2 md_password=pgwatch2admin md_password_type=plain-text md_preset_config_name=basic md_is_enabled=true new=New >/dev/null
echo "OK"


echo "sleeping 180s..."
sleep 180


echo "checking if metrics exists for added DB..."
if [ $METRICDBTYPE == "pg" ]; then
    ROWS=$(psql -qXAtc "SELECT count(distinct dbname) FROM db_stats WHERE dbname LIKE 'smoke%'")
else
  ROWS=$(curl -sG http://$LOCALHOST:$INFLUXPORT/query?pretty=true --data-urlencode "db=pgwatch2" \
  --data-urlencode "q=SELECT count(xlog_location_b) FROM wal WHERE dbname='smoke1'" \
  | jq .results[0].series[0].values[0][1])
fi
if [ -z $ROWS -o ! $ROWS -gt 1 ] ; then
  echo "could not get any db_stats rows for the inserted smoke DBS'"
  exit 1
fi
echo "$ROWS rows found from db_stats"


echo "image $CONTAINER_NAME looks OK"


echo "shutting down image..."
docker stop "$CONTAINER_NAME"
sleep 5
echo "OK. Done"
