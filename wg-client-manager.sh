#!/usr/bin/env bash
# Add and delete wireguard peers
# Author: Nikita Wootten <nikita.wootten@gmail.com>

set -e -o pipefail # fail on error or undeclared var
readonly script_name=$(basename "${0}")
readonly script_dir=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )

# name of wireguard interface
wg_interface="wg0"
# base directory for client config files
base_dir="./client"

function print_usage {
    echo "Usage:"
    echo "  ${script_name} -h               Display this help message"
    echo "  ${script_name} -i <interface>   Set Wireguard interface (default: wg0)"
    echo "  ${script_name} -b <base_dir>    Set client configuration base directory (default: ./client)"
    echo "  ${script_name} add <client>     Add Wireguard client"
    echo "  ${script_name} remove <client>  Remove Wireguard client"
    exit 0
}

# prompt [y/n]
# via https://stackoverflow.com/a/32708121
function prompt_confirm {
    while true; do
        read -r -n 1 -p "${1:-Continue?} [y/n]: " REPLY
        case $REPLY in
            [yY]) echo ; return 0 ;;
            [nN]) echo ; return 1 ;;
            *) printf " \033[31m %s \n\033[0m" "invalid input"
        esac
    done
}

# use perl to substitute ${} in given file
# via https://stackoverflow.com/a/2916159
function use_template {
    perl -p -e 's/\$\{([^}]+)\}/defined $ENV{$1} ? $ENV{$1} : $&/eg' < $1
}

ipv4_first_valid_address="10.100.0.2"

function generate_ipv4_addr {
    # get last client's ip address
    local current_addr=$(sudo wg show ${wg_interface} allowed-ips | cut -f2 | cut -d ' ' -f1 | cut -d '/' -f1 | tail -n1)
    # if no clients, use ipv4_first_valid_address
    if [[ -z ${current_addr} ]] ; then
        current_addr=${ipv4_first_valid_address}
    fi
    # generate next ip (via https://stackoverflow.com/a/43196141)
    local current_addr_hex=$(printf '%.2X%.2X%.2X%.2X\n' `echo ${current_addr} | sed -e 's/\./ /g'`)
    local next_addr_hex=$(printf %.8X `echo $(( 0x${current_addr_hex} + 1 ))`)
    local next_addr=$(printf '%d.%d.%d.%d\n' `echo ${next_addr_hex} | sed -r 's/(..)/0x\1 /g'`)
    echo ${next_addr}
}

ipv6_first_valid_address="fd08:4711::2"

function generate_ipv6_addr {
    # get last client's ip address
    local current_addr=$(sudo wg show ${wg_interface} allowed-ips | cut -f2 | cut -d ' ' -f2 | cut -d '/' -f1 | tail -n1)
    # if no clients, use ipv4_first_valid_address
    if [[ -z ${current_addr} ]] ; then
        current_addr=${ipv6_first_valid_address}
    fi
    # generate next ip
    local current_addr_hex=$(printf '%04x%04x%04x%04x\n' `echo ${current_addr} | sed -e 's/\:\:/\:0\:/g' | sed -e 's/\:/ /g' | sed -e 's/$| / /g' | sed -e 's/[^ ]* */0x&/g'`)
    local next_addr_hex=$(printf %.16X `echo $(( 0x${current_addr_hex} + 1 ))`)
    local next_addr=$(printf '%04x:%04x:%04x:%04x\n' `echo ${next_addr_hex} | sed -r 's/(....)/0x\1 /g'` | sed -r 's/\:0+/:/g')
    echo ${next_addr}
}

while getopts ":hi:b:" opt; do
    case ${opt} in
        h)
            print_usage
            ;;
        i)
            wg_interface=${OPTARG}
            ;;
        b)
            base_dir=${OPTARG}
            ;;
        \?)
            echo "Invalid Option: -${OPTARG}" 1>&2
            exit 1
            ;;
        :)
            echo "Invalid Option: -${OPTARG} requires an argument" 1>&2
            exit 1
            ;;
    esac
done
shift $((OPTIND -1))

subcommand=$1; shift || true
case "$subcommand" in
    add)
        client=$1; shift || true
        if [[ -z ${client} ]] ; then
            echo "Client name must be specified" 1>&2
            exit 1
        fi

        (
        
        mkdir -p ${base_dir}/${client}

        echo "Generating keys..."
        export private_key=$(wg genkey | tee "${base_dir}/${client}/${client}.key")
        export public_key=$(echo ${private_key} | wg pubkey | tee "${base_dir}/${client}/${client}.pub")
        export preshared_key=$(wg genpsk | tee "${base_dir}/${client}/${client}.psk")

        echo "Assigning ip addresses..."
        export ipv4=$(generate_ipv4_addr)
        export ipv6=$(generate_ipv6_addr)
        echo "Client will have address ${ipv4} ${ipv6}"

        echo "Adding client to peer list"
        sudo wg set ${wg_interface} peer ${public_key} preshared-key "${base_dir}/${client}/${client}.psk" allowed-ips ${ipv4}/32,${ipv6}/128

        echo "Generating client config"
        use_template ${script_dir}/wg-client.template.conf > ${base_dir}/${client}/${client}.conf
        
        qrencode -t ansiutf8 -r "${base_dir}/${client}/${client}.conf"

        )
        ;;
    remove)
        client=$1; shift || true
        if [[ -z ${client} ]] ; then
            echo "Client name must be specified" 1>&2
            exit 1
        fi

        # check to see that the given client configuration directory exists
        if [[ ! -d "${base_dir}/${client}" ]] ; then
            echo "Error: Configuration for client ${client} does not exist in ${base_dir}." 1>&2
            exit 1
        fi

        prompt_confirm "Removing ${client} from ${wg_interface}... Continue?" || exit 0
        sudo wg set ${wg_interface} peer $(cat ${base_dir}/${client}/${client}.pub) remove
        echo "Client removed."

        prompt_confirm "Deleting ${client} configuration from ${base_dir}/${client}... This action is irreversible. Continue?" || exit 0
        rm -fr -- "${base_dir}/{$client}"
        echo "Client configuration deleted."
        ;;
    *)
        echo "Unknown option '${subcommand}'"
        ;;
esac