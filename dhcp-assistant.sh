#!/usr/bin/env bash
#
# Setups up an interface as dhcp server and allows for a device to be plugged
# into a layer 2 switch or device (e.g. raspberry pi)


###############################################################################
# Globals:
#   ADAPTERS
#   CHOICE
#   DHCP_CONFIG_PATH
#   REQUIRED_PROGRAMS
#   DHCP_CONFIG
###############################################################################

declare -a ADAPTERS
declare -i CHOICE

# Location of config file
declare -r DHCP_CONFIG_PATH="./udhcpd.conf"

# List of required installed programs
declare -a REQUIRED_PROGRAMS=("udhcpd")

# CONFIG
declare -r IP_ADDR="172.168.10.1"
declare -r NMASK="255.255.255.0"
declare -r BMASK="172.168.10.255"

#config file
declare -r DHCP_CONFIG="
# range
start 172.168.10.100
end 172.168.10.200

max_leases 40

# Interface
interface eth0

option subnet 255.255.255.0
option router 172.168.10.1
option lease 43200
option dns 172.168.10.1
option domain local

pidfile /var/run/udhcpd.pid
"

RUN_IN_FOREGROUND="-f"

# Capture control-C
trap control_c INT

###############################################################################
# FUNCTION: check_install
# DESCRIPTION: checks for applications and for config file
###############################################################################
function check_install() {

    install_choice="y"
    for program in ${REQUIRED_PROGRAMS[@]}; do
        if ! [ -x "$(command -v ${program})" ]; then

            echo "Error: ${program} is not installed." >&2
            printf "Would you like to attempt to install ${program}?\n"

            printf "\nDefault [y]\n"
            read -p "[y/N] : " install_choice
            printf "\n"

            install_choice=${install_choice:-"y"}

            if [ $install_choice == "y" ]; then
                printf "installing %s\n" $program

                apt-get install ${program} --assume-yes

                if [ $? != 0 ]; then
                    printf "Installing ${program} Failed. exiting."
                    exit 1
                fi
            else
                printf "Install ${program} and try again."
                exit 1
            fi
        fi
    done

    # not sure if this is needed
    # disable udhcpd from running as a service
    update-rc.d udhcpd remove

    # If config doesn't exist install it
    if [ ! -f ${DHCP_CONFIG_PATH} ]; then
        touch ${DHCP_CONFIG_PATH}
        > ${DHCP_CONFIG_PATH}

        echo -e "${DHCP_CONFIG}" >> ${DHCP_CONFIG_PATH}
    fi

}

###############################################################################
# FUNCTION: uninstall
# DESCRIPTION: remove the config script and attempt uninstall of programs
###############################################################################
function uninstall() {

    # Remove config
    rm ${DHCP_CONFIG_PATH}

    # Uninstall programs
    uninstall_choice="y"
    for program in ${REQUIRED_PROGRAMS[@]}; do
        if  [ -x "$(command -v ${program})" ]; then
            printf "${program} is installed.\n"
            printf "Would you like to attempt to uninstall ${program}?\n"

            printf "\nDefault [y]\n"
            read -p "[y/N] : " uninstall_choice
            printf "\n"

            uninstall_choice=${uninstall_choice:-"y"}

            if [ $uninstall_choice == "y" ]; then
                printf "uninstalling %s\n" $program
                apt-get remove ${program} --assume-yes

                if [ $? != 0 ]; then
                    printf "Uninstalling ${program} Failed. exiting."
                    exit 1
                fi
            else
                printf "Uninstall ${program} and try again."
                exit 1
            fi
        fi
    done

}


###############################################################################
# FUNCTION: menu
# DESCRIPTION: Prompts user for choice of NICs
###############################################################################
function menu() {

    printf "\n==========================\n"
    printf "       DHCP ASSISTANT"
    printf "\n==========================\n\n"


    printf "Select Adapter:\n"
    ADAPTERS=($(ls "/sys/class/net"))

    id=0
    for adapter in ${ADAPTERS[@]}; do
        printf "\t[%d] %s\n" ${id} ${adapter}
        let id=$id+1
    done

    printf "\n"
    printf "Default: ${ADAPTERS[0]}\n"
    read -p "Choice: " CHOICE
    printf "\n"

    #Set Default to 0
    CHOICE=${CHOICE:0}
}

###############################################################################
# FUNCTION: kill_existing_dhcp_server
# DESCRIPTION: checks for an existing dhcp server
###############################################################################
function kill_existing_dhcp_server() {
    # kill dhcp client
    if [ -f "/var/run/udhcpd.${adapter}.pid" ]; then
        #try to kill don't care about output
        kill `cat /var/run/udhcpd.${adapter}.pid` > /dev/null 2>&1
        rm "/var/run/udhcpd.${adapter}.pid" > /dev/null 2>&1
    fi
}


###############################################################################
# FUNCTION: control_firewall
# ARGUMENTS: STATE, PORT
# DESCRIPTION: opens and allows traffic through firewall for dhcp
###############################################################################
function control_firewall() {
    # 67 : dhcp
    ufw $1 $2/udp
    ufw reload
    ufw status
}


###############################################################################
# FUNCTION: control_c
# DESCRIPTION: captures the control_c from user to begin cleanup
###############################################################################
function control_c() {
    control_firewall "deny" 67
    control_dhcp "stop"
    exit
}

###############################################################################
# FUNCTION: control_dhcp
# ARGUMENTS START/STOP
# DESCRIPTION: checks for applications and for config file
###############################################################################
function control_dhcp() {

    adapter=${ADAPTERS[CHOICE]}

    kill_existing_dhcp_server

    if [ $1 == "start" ]; then
        # configure interface
        ifconfig ${adapter} ${IP_ADDR} netmask ${NMASK} broadcast ${BMASK} up

        printf "\n\nYour IP Address: ${IP_ADDR}\n\n"

        if [ $RUN_IN_FOREGROUND == ""]; then
            printf "Running in the Background..\n"
        fi
        # Start the DHCP Server Process once the Interface is Ready with the IP Add
        udhcpd "${DHCP_CONFIG_PATH}" ${RUN_IN_FOREGROUND}


    elif [ $1 == "STOP" ]; then
        :
        # pass
        # kill_existing_dhcp_server ^^
    fi
}


###############################################################################
# FUNCTION: helpMenu
# DESCRIPTION: displays the help menu
###############################################################################
function usage() {
    printf "\n==========================\n"
    printf "       DHCP ASSISTANT"
    printf "\n==========================\n\n"

    printf "This script setups up an interface as dhcp server and allows\n"
    printf "for a device to be plugged into a layer 2 switch\n"
    printf "\n"

    printf "Help Menu:\n"
    printf "\t[no args]\trun the script\n"
    printf "\t-u\t\tuninstall\n"
    printf "\t-h\t\thelp menu (this thing)\n"
    printf "\tctr-c\t\texit the program\n"
}


###############################################################################
# FUNCTION: handle_usage
# DESCRIPTION: handle arguments
###############################################################################
function handle_usage() {

    while getopts ":ukbh" opt; do
        case ${opt} in
            u )
                # uninstall everything
                uninstall
                exit;
                ;;
            k )
                # kill an existing dhcp server
                menu
                control_c
                # Kill existing dhcp server
                # Close Ports
                ;;
            b )
                RUN_IN_FOREGROUND=""
                # run in the background
                ;;
            h | * )
                helpMenu
                exit;
                ;;
        esac
    done

    shift $((OPTIND-1))

}


###############################################################################
# FUNCTION: main
# DESCRIPTION: main function for script
###############################################################################
function main() {

    if [[ $EUID -ne 0 ]]; then
       echo "This script must be run as root"
       exit 1
    fi

    handle_usage "$@"

    #Check to make sure everything is installed
    check_install

    CHOICE=0
    #Get user input
    menu

    # Allow the firewall
    control_firewall "allow" 67

    adapter=${ADAPTERS[CHOICE]}
    # updated config with option
    sed -i "s,interface.*,interface ${adapter},g" "${DHCP_CONFIG_PATH}" >> "${DHCP_CONFIG_PATH}"

    sed -i "s,pidfile.*,pidfile /var/run/udhcpd.${adapter}.pid,g" "${DHCP_CONFIG_PATH}" >> "${DHCP_CONFIG_PATH}"

    control_dhcp "stop"
    control_dhcp "start"
   }

#pass all arguments
main "$@"
