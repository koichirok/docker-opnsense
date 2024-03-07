# shellcheck shell=bash

__DIR__="$(dirname "$(realpath "${BASH_SOURCE[0]}")")"

select_fastest_mirror() {
    local mirrors top3
    read -r -d '' mirrors < "${__DIR__}/mirrors.txt" || :

    # shellcheck disable=SC2086
    top3="$(netselect -s 3 -t 10 $mirrors 2> /dev/null)"

    # return the fastest mirror only
    echo "${top3}" | awk 'NR==1{print $2}'
}

# usage: get_product_series <version>
get_product_series() {
    echo "$1" | cut -d. -f1-2
}

# usage: process_argument <spec> <args...>
# Perl's Getopt::Std-like argument processing
getopts_std() {
    local spec
    spec="${1}"
    shift
    while getopts "${spec}" opt; do
        case "${opt}" in
            ?)
                if [ "${OPTARG}" ]; then
                    eval "opt_${opt}=\"${OPTARG}\""
                else
                    eval "opt_${opt}=true"
                fi
        esac
    done
}

# usage: raw_image_name <version> [-t type] [-a arch]
build_release_image_name() {
    local series opt_t opt_a
    series="$(get_product_series "$1")"
    shift
    getopts_std "t:a:" "$@"
    : "${opt_t:="nano"}"
    : "${opt_a:="amd64"}"
    echo "OPNsense-${series}-${opt_t}-${opt_a}.img"
}

# usage: raw_image_url <version> [-m mirror] [-t type] [-a arch]
build_release_image_url() {
    local version opt_m opt_t opt_a
    version="$1"
    shift
    getopts_std "m:t:a:" "$@"
    : "${opt_t:="nano"}"
    : "${opt_a:="amd64"}"
    : "${opt_m:="$(chose_fastest_mirror)"}"
    echo "${opt_m}/releases/$(get_product_series "$version")/$(build_release_image_name "${version}" -t "${opt_t}" -a "${opt_a}").bz2"
}

build_release_checksum_url() {
    local series opt_m opt_a
    series="$(get_product_series "$1")"
    shift
    getopts_std "m:a:" "$@"
    : "${opt_a:="amd64"}"
    : "${opt_m:="$(chose_fastest_mirror)"}"
    echo "${opt_m}/releases/${series}/OPNsense-${series}-checksums-${opt_a}.sha256"
}
