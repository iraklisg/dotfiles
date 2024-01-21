#!/usr/bin/env zsh

DATABASE_USER=${PGUSER:-iraklis}
DATABASE_PASSWORD=${PGPASSWORD:-secret}
DATABASE_HOST=${PGHOST:-postgis}
DATABASE_PORT=${PGPORT:-5432}
DATABASE_DOCKER_NETWORK=postgis-network
BROWSERSTACK_KEY=${BROWSERSTACK_ACCESS_KEY}

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
    echo "  hylo <command> [options] [arguments]"
    echo
    echo "${_color_yellow}Database Commands:${_nc}"
    echo "  ${_color_green}hylo db:start${_nc}              Start docker postgis container"
    echo "  ${_color_green}hylo db:create DATABASE${_nc}    Create a new database"
    echo "  ${_color_green}hylo db:psql COMMAND${_nc}       Run psql command"
    echo
    echo "${_color_yellow}Server Commands:${_nc}"
    echo "  ${_color_green}hylo server:commit-check SERVER_NAME${_nc}   Check latest commit on remote server"
    echo "  ${_color_green}hylo server:branch-check SERVER_NAME${_nc}   Check current branch on remote server"
    echo "  ${_color_green}hylo server:locale-check SERVER_NAME${_nc}   Check for untracked locale files on remote server"
    echo "  ${_color_green}hylo server:locale-push SERVER_NAME${_nc}    Push locale files from remote server"
    echo
    echo "${_color_yellow}Browserstack Commands:${_nc}"
    echo "  ${_color_green}hylo bs:start SERVER_NAME${_nc}   Start broserstack local"
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
        echo -e "${_color_red}Invalid server name format${_nc}"
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

    echo "${_color_blue}Connecting to ${_bold}$server_name as $remote_user${_nc}...\n"

    ssh "${server_name}" "su - ${remote_user} -c 'cd project/${remote_project_dir}/ && ${command}'"
}

if [ "$#" -gt 0 ]; then
    if [ "$1" = "help" ]; then
        display_help

    # Start docker postgis container
    elif [ "$1" = "db:start" ]; then
        docker run -d \
            --restart always \
            --name ${DATABASE_HOST} \
            --network ${DATABASE_DOCKER_NETWORK} \
            -e POSTGRES_PASSWORD=${DATABASE_PASSWORD} \
            -e POSTGRES_USER=${DATABASE_USER} \
            -p 127.0.0.1:${DATABASE_PORT}:5432 \
            -v postgis-data:/var/lib/postgresql/data \
            postgis/postgis:16-3.4

    # Proxy createdb commands
    elif [ "$1" = "db:create" ]; then
        shift 1
        docker run -it --rm \
            --network ${DATABASE_DOCKER_NETWORK} \
            -e PGPASSWORD=${DATABASE_PASSWORD} \
            postgis/postgis:16-3.4 createdb -h ${DATABASE_HOST} -U ${DATABASE_USER} "$@"

    # Proxy psql commands
    elif [ "$1" = "db:psql" ]; then
        shift 1
        docker run -it --rm \
            --network ${DATABASE_DOCKER_NETWORK} \
            -e PGPASSWORD=${DATABASE_PASSWORD} \
            postgis/postgis:16-3.4 psql -h ${DATABASE_HOST} -U ${DATABASE_USER} "$@"

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
                echo -e \"${_color_red}Untracked LC_MESSAGES files found.${_nc}\"
            else
                echo -e \"${_color_green}No untracked LC_MESSAGES files found.${_nc}\"
            fi"

        run_command_via_ssh "$server_name" "$command"
    
    elif [ "$1" = "server:locale-push" ]; then
        shift 1
        local server_name="$@"
        local command="
            if git status --porcelain | grep -q \"locale/.*LC_MESSAGES/django\\.\(po\\|mo\)\"; then
                echo -e \"${_color_red}Untracked LC_MESSAGES files found.${_nc}\"

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
        if [[ -z "$BROWSERSTACK_ACCESS_KEY" ]]; then
            echo "${RED}BROWSERSTACK_ACCESS_KEY is not set.${NC}"
            exit 1
        fi
        /opt/browserstack/BrowserStackLocal --key "$BROWSERSTACK_ACCESS_KEY"

    else
        echo -e "${_color_red}Invalid argument: $@${_nc}"
        display_help
    fi
else
    display_help
fi
