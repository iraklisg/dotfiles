#!/usr/bin/env zsh

_DATABASE_USER=${HYLO_POSTGRES_USER:-iraklis}
_DATABASE_PASSWORD=${HYLO_POSTGRES_PASSWORD:-secret}
_DATABASE_PORT=5432
_DOCKER_DATABASE_HOST=${HYLO_DOCKER_POSTGRES_HOST:-hylo-postgis}
_DOCKER_DATABASE_PORT=${HYLO_DOCKER_POSTGRES_PORT:-5432}
_DOCKER_DATABASE_NETWORK=${HYLO_DOCKER_POSTGRES_NETWORK:-hylo-postgis-network}

_BROWSERSTACK_KEY=${BROWSERSTACK_ACCESS_KEY}

_BOLD="$(tput bold)"
_COLOR_GREEN="\033[0;32m"
_COLOR_BLUE="\033[0;34m"
_COLOR_RED="\033[0;31m"
_COLOR_YELLOW="\033[0;33m"
_NC="\033[0m"

function display_help() {
    echo "${_BOLD}Helper script for hylo development${_NC}"
    echo
    echo "${_COLOR_YELLOW}Usage:${_NC}"
    echo "  hylo <command> [options] [arguments]"
    echo
    echo "${_COLOR_YELLOW}Database Commands:${_NC}"
    echo "  ${_COLOR_GREEN}hylo db:start${_NC}              Start docker postgis container"
    echo "  ${_COLOR_GREEN}hylo db:create DATABASE${_NC}    Create a new database"
    echo "  ${_COLOR_GREEN}hylo db:psql COMMAND${_NC}       Run psql command"
    echo
    echo "${_COLOR_YELLOW}Proxy Commands:${_NC}"
    echo "  ${_COLOR_GREEN}hylo proxy:start${_NC}   Start docker reverse proxy"
    echo
    echo "${_COLOR_YELLOW}Server Commands:${_NC}"
    echo "  ${_COLOR_GREEN}hylo server:commit-check SERVER_NAME${_NC}   Check latest commit on remote server"
    echo "  ${_COLOR_GREEN}hylo server:branch-check SERVER_NAME${_NC}   Check current branch on remote server"
    echo "  ${_COLOR_GREEN}hylo server:locale-check SERVER_NAME${_NC}   Check for untracked locale files on remote server"
    echo "  ${_COLOR_GREEN}hylo server:locale-push SERVER_NAME${_NC}    Push locale files from remote server"
    echo
    echo "${_COLOR_YELLOW}Browserstack Commands:${_NC}"
    echo "  ${_COLOR_GREEN}hylo bs:start SERVER_NAME${_NC}   Start broserstack local"
    echo
    exit 1
}

# Parse server name and sets `project`, `datahub` and `environment` variables
# 
# Servername format: hylo-<project>[-datahub]-<environment>
# Example: hylo-tanzdigital-staging
# Example: hylo-tanzdigital-datahub-staging
#
function set_project_details() {
    local server_name="$1"
    local - a parts
    parts=("${(@s/-/)server_name#hylo-}")

    if [[ ${#parts[@]} -eq 3 ]]; then
        project="${parts[1]}"
        datahub=true
        environment="${parts[3]}"
    elif [[ ${#parts[@]} -eq 2 ]]; then
        project="${parts[1]}"
        datahub=false
        environment="${parts[2]}"
    else
        echo -e "${_COLOR_RED}Invalid server name format${_NC}"
        exit 1
    fi
}

# Sets `remote_user` and `remote_project_dir` variables
# Accepts `datahub` boolean
#
function set_remote_details() {
    local datahub="$1"

    if [[ "$datahub" == false ]]; then
        remote_user="$project"
        remote_project_dir="$project"
    else
        remote_user="data_hub"
        remote_project_dir="data_hub"
    fi
}

# Run command on remote server via ssh
# Accepts server name and command
#
function run_command_via_ssh() {
    local server_name="$1"
    local command="$2"

    local project
    local datahub
    local environment
    set_project_details "$server_name"

    local remote_user
    local remote_project_dir
    set_remote_details "$datahub"

    echo "${_COLOR_BLUE}Connecting to ${_BOLD}$server_name as $remote_user${_NC}...\n"

    ssh "${server_name}" "su - ${remote_user} -c 'cd project/${remote_project_dir}/ && ${command}'"
}

function main() {
    if [ "$#" -gt 0 ]; then
        if [ "$1" = "help" ]; then
            display_help

        # Start docker postgis container
        elif [ "$1" = "db:start" ]; then
            docker run -d \
                --restart always \
                --name ${_DOCKER_DATABASE_HOST} \
                --network ${_DOCKER_DATABASE_NETWORK} \
                -e POSTGRES_PASSWORD=${_DATABASE_PASSWORD} \
                -e POSTGRES_USER=${_DATABASE_USER} \
                -p 127.0.0.1:${_DATABASE_PORT}:${_DOCKER_DATABASE_PORT} \
                -v hylo-postgis-data:/var/lib/postgresql/data \
                postgis/postgis:16-3.4

        # Proxy createdb commands
        elif [ "$1" = "db:create" ]; then
            shift 1
            docker run -it --rm \
                --network ${_DOCKER_DATABASE_NETWORK} \
                -e PGPASSWORD=${_DATABASE_PASSWORD} \
                postgis/postgis:16-3.4 createdb -h ${_DOCKER_DATABASE_HOST} -U ${_DATABASE_USER} "$@"

        # Proxy psql commands
        elif [ "$1" = "db:psql" ]; then
            shift 1
            docker run -it --rm \
                --network ${_DOCKER_DATABASE_NETWORK} \
                -e PGPASSWORD=${_DATABASE_PASSWORD} \
                postgis/postgis:16-3.4 psql -h ${_DOCKER_DATABASE_HOST} -U ${_DATABASE_USER} "$@"

        # Start reverse proxy
        elif [ "$1" = "proxy:start" ]; then
            shift 1
            docker run -d \
                --restart always \
                --name hylo-proxy \
                --network "host" \
                -v ${XDG_CONFIG_HOME}/nginx/conf.d/hylo-docker.conf:/etc/nginx/conf.d/default.conf \
                nginx:1.19

        elif [ "$1" = "server:commit-check" ]; then
            shift 1
            local server_name="$@"
            local command="git log -1"

            run_command_via_ssh "$server_name" "$command"

        elif [ "$1" = "server:branch-check" ]; then
            shift 1
            local server_name="$@"
            local command="git rev-parse --abbrev-ref HEAD"

            run_command_via_ssh "$server_name" "$command"

        elif [ "$1" = "server:locale-check" ]; then
            shift 1
            local server_name="$@"
            local command="
                if git status --porcelain | grep -q \"locale/.*LC_MESSAGES/django\\.\(po\\|mo\)\"; then
                    echo -e \"${_COLOR_RED}Untracked LC_MESSAGES files found.${_NC}\"
                else
                    echo -e \"${_COLOR_GREEN}No untracked LC_MESSAGES files found.${_NC}\"
                fi"

            run_command_via_ssh "$server_name" "$command"
        
        elif [ "$1" = "server:locale-push" ]; then
            shift 1
            local server_name="$@"
            local command="
                if git status --porcelain | grep -q \"locale/.*LC_MESSAGES/django\\.\(po\\|mo\)\"; then
                    echo -e \"${_COLOR_RED}Untracked LC_MESSAGES files found.${_NC}\"

                    echo \"Attempt to merge remote changes.\"
                    # Fetch the latest changes without merging
                    git fetch origin

                    # Attempt to merge without committing
                    git merge --no-commit --no-ff origin/master

                    # Check if there are merge conflicts
                    if git ls-files -u | grep -q \"^\"; then
                        echo \"Merge conflicts detected. Aborting merge.\"
                        git merge --abort
                        exit 1
                    else
                        echo \"No conflicts. Proceeding.\"

                        # Add the translation files
                        git add locale/de/LC_MESSAGES/django.po locale/de/LC_MESSAGES/django.mo

                        # Commit the changes
                        git commit -m \"🌐 Translations\"

                        # Push the changes
                        git push
                    fi
                else
                    echo \"No untracked LC_MESSAGES files found. No action taken.\"
                fi"

            run_command_via_ssh "$server_name" "$command"

        elif [ "$1" = "bs:start" ]; then
            if [[ -z "$_BROWSERSTACK_KEY" ]]; then
                echo "${RED} Browserstack access key is not set.${NC}"
                exit 1
            fi
            /opt/browserstack/BrowserStackLocal --key "$_BROWSERSTACK_KEY"

        else
            echo -e "${_COLOR_RED}Invalid argument: $@${_NC}"
            display_help
        fi
    else
        display_help
    fi
}

main "$@"
