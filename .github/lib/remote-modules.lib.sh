#!/bin/env bash

# build-include res/source-header.txt

function modules.std.log() {
    local -r level="$1"
    local -r message="$2"
    local -r timestamp=$(date +"%Y-%m-%d %H:%M:%S")
    local -r script="$(basename "$0")"

    [[ ${modules_log_all_priorities[$level]} ]] || return 1
    (( ${modules_log_all_priorities[$level]} < ${modules_log_all_priorities[$MODULES_LOG_PRIORITY]} )) && return 2 
    
    echo -e "${timestamp} [${level}] [$script] ${message}" >> ${MODULES_LOG_PATH}/${MODULES_LOG_FILE}
}

function modules.remote-modules.check_url_status() {
    local -r url="$1"
    
    local rcommands=${remote_commands[$MODULES_REMOTE_COMMAND]}

    if $(command -v wget > /dev/null) ; then
        status="$(wget -O- __url__ 2>&1 | egrep 'HTTP|Length|saved')"
        [[ "$status" == *"200 OK"* ]] && return 1 || return 0
    elif $(command -v curl > /dev/null) ; then 
        status="$(curl --location --silent --output ${tmpfile} -w "%{response_code}" ${url})"
        [[ "$status" == "200" ]] && return 1 || return 0
    else
        modules.std.log "SEVERE" "No wget or curl found on path."
        return 0
    fi
}

# Downloads a remote module from github and returns the path to the file 
#
# Usage: modules.remote-modules.url <url>
function modules.remote-modules.url() {
    local -r url="$1"
    local -r lib=`basename ${url}`
    local -r dest="${LIB_DIR}/${lib}"
    local -r tmpfile=$(mktemp)
    
    local existing_hash
    local download_hash

    # First check to see if the file already exists, if it does, we'll get a hash of the current lib to compare to 
    [[ -f "${dest}" ]] && existing_hash="$(md5sum ${dest} | cut -d' ' -f1)" && modules.std.log "INFO" "Library ${dest} has hash: ${existing_hash}" || modules.std.log "TRACE" "Library ${dest} not found"

    # If there's a .md5 file stored next to the target library, we can use that to check if it's different
    [[ $(modules.remote-modules.check_url_status "${url}.md5") ]] && modules.std.log "INFO" "Found md5 remote" || modules.std.log "INFO" "Module does not have a remote md5, will download anyways"

    if $(command -v wget > /dev/null) ; then
        modules.std.log "TRACE" "Using wget to fetch ${url}"
        status=$(wget -O- ${url} 2>&1 | egrep 'HTTP|Length|saved')
        modules.std.log "TRACE" "${url} ${status}"
        if [[ "$status" == *"200 OK"* ]]; then
            wget -q -O ${tmpfile} ${url} || { modules.std.log "SEVERE" "Error downloading the script" ; exit 1 ; }
            modules.std.log "TRACE" "Downloaded ${url} to ${tmpfile}"
        else
            modules.std.log "SEVERE" "Unable to retrieve ${url} -- Got $result"
            return 0
        fi
    elif $(command -v curl > /dev/null) ; then
        [[ "$(curl --silent --output ${tmpfile} -w "%{http_code}" ${url})" ]] && echo $dest && return 
    else
        modules.std.log "ERROR" "No Curl or WGet on path."
    fi

    download_hash=`md5sum $tmpfile | cut -d' ' -f1` || { module.std.log "SEVERE" "Unable to generate a hash -- ${download_hash}" ; exit 1 ; }
    modules.std.log "DEBUG" "Hash for downloaded file is ${download_hash}"

    if [ -f "${dest}" ] && [ "${existing_hash}" != "${download_hash}" ]; then
        modules.std.log "INFO" "Downloaded script is different, backing up existing script and overwriting"
        mv ${dest} ${dest}.bak.`date +"%Y-%m-%d-%H%M%S"`
        mv ${tmpfile} ${dest}
        echo ${dest}
        return 1
    elif [ -f "${dest}" ] && [ "${existing_hash}" == "${download_hash}" ]; then
        modules.std.log "INFO" "Downloaded script has the same hash, not replacing"
        echo ${dest}
        return 2
    else
        modules.std.log "INFO" "Successfully downloaded ${dest} from ${url}"
        mv ${tmpfile} ${dest}
        echo ${dest}
        return 3
    fi


    modules.std.log "SEVERE" "Unable to retreive the script at ${url}" 
}

function modules.remote-modules.__get_remote_command() {
    echo $MODULES_REMOTE_COMMAND
}

[[ -z "${LIB_DIR}" ]] && LIB_DIR="${HOME}/.bash-modules/lib"
mkdir -p ${LIB_DIR}

if [ -z "$MODULES_LOG_FILE" ]; then
    MODULES_LOG_FILE="$(basename $0)"    
fi

if [ -z "$MODULES_LOG_PATH" ]; then
    MODULES_LOG_PATH="${HOME}/.bash-modules/log"
fi

if [ -z "$MODULES_LOG_PRIORITY" ]; then
    MODULES_LOG_PRIORITY=DEBUG
fi
mkdir -p ${MODULES_LOG_PATH}

declare -A modules_log_all_priorities=([TRACE]=0 [DEBUG]=1 [INFO]=2 [WARN]=3 [ERROR]=4 [SEVERE]=5 [CRITICAL]=6)

if $(command -v wget > /dev/null); then MODULES_REMOTE_WGET_AVAIL=1 ; modules.std.log "DEBUG" "Found wget at $(which wget)" ; else modules.std.log "DEBUG" "No wget found" ; fi
if $(command -v curl > /dev/null); then MODULES_REMOTE_CURL_AVAIL=1 ; modules.std.log "DEBUG" "Found curl at $(which curl)" ; else modules.std.log "DEBUG" "No curl found" ; fi

if [ $MODULES_REMOTE_WGET_AVAIL ]; then 
    MODULES_REMOTE_COMMAND=wget
elif [ $MODULES_REMOTE_CURL_AVAIL ]; then
    MODULES_REMOTE_COMMAND=curl 
fi

declare -A curl_command=(
    [download]="" 
    [fetch_md5]="" 
    [check_status]=""
)

declare -A wget_command=(
    [download]=""
    [fetch_md5]=""
    [check_status]=""
)

declare -A remote_commands=(
    [curl]=${curl_command}
    [wget]=${wget_command}
)

modules.std.log "TRACE" "Source file loaded with arguments $@"

GETOPT=$(getopt -o R: --long remote-command: -n "remote-modules" -- "$@")

if [ $? != 0 ] ; then modules.std.log "SEVERE" "Unable to parse arguments, ignoring" ; IGNORE_ARGS=1 ; fi

if [ ! ${IGNORE_ARGS} ]; then
    eval set -- "$GETOPT"

    while true; do
        case "$1" in
            -R | --remote-command ) 
                MODULES_REMOTE_COMMAND="$2"
                modules.std.log "INFO" "Remote command forced to ${MODULES_REMOTE_COMMAND}"
                shift ;;
            -- ) shift; break ;;
            * ) break ;;
        esac
    done
fi

modules.std.log "INFO" "Using $MODULES_REMOTE_COMMAND for fetching remote content"