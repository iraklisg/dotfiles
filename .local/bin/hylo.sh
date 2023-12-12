#!/usr/bin/env zsh

DATABASE_USER=iraklis
DATABASE_PASSWORD=${PGPASSWORD:-secret}
DATABASE_HOST=postgis
DATABASE_PORT=5432
DOCKER_DATABASE_NETWORK=postgis-network

_bold="$(tput bold)"
_color_green="\033[0;32m"
_color_blue="\033[0;34m"
_color_red="\033[0;31m"
_color_yellow="\033[0;33m"
_nc="\033[0m"

function display_help() {
    echo "${_bold}Helper script for hylo development${_nc}"
    echo
    echo "${_color_yellow}Usage:${_nc}"
    echo "  ./hylo.sh <command> [options] [arguments]"
    echo
    echo "${_color_yellow}Commands:${_nc}"
    echo "  ${_color_green}db:start${_nc}    Start docker postgis container"
    echo "  ${_color_green}db:create DATABASE${_nc}   Create a new database"
    echo "  ${_color_green}psql COMMAND${_nc}    Run psql"
    exit 1
}

if [ "$#" -gt 0 ]; then
    if [ "$1" = "help" ]; then
        display_help

    # Start docker postgis container
    elif [ "$1" = "db:start" ]; then
        docker run -d \
            --restart always \
            --name ${DATABASE_HOST} \
            --network ${DOCKER_DATABASE_NETWORK} \
            -e POSTGRES_PASSWORD=${DATABASE_PASSWORD} \
            -e POSTGRES_USER=${DATABASE_USER} \
            -p 127.0.0.1:${DATABASE_PORT}:5432 \
            -v postgis-data:/var/lib/postgresql/data \
            postgis/postgis:16-3.4

    # Proxy createdb commands
    elif [ "$1" = "db:create" ]; then
        shift 1
        docker run -it --rm \
            --network ${DOCKER_DATABASE_NETWORK} \
            -e PGPASSWORD=${DATABASE_PASSWORD} \
            postgis/postgis:16-3.4 createdb -h ${DATABASE_HOST} -U ${DATABASE_USER} "$@"

    # Proxy psql commands
    elif [ "$1" = "psql" ]; then
        shift 1
        docker run -it --rm \
            --network ${DOCKER_DATABASE_NETWORK} \
            -e PGPASSWORD=${DATABASE_PASSWORD} \
            postgis/postgis:16-3.4 psql -h ${DATABASE_HOST} -U ${DATABASE_USER} "$@"

    else
        echo "Invalid argument: $1"
        display_help
    fi
else
    display_help
fi
