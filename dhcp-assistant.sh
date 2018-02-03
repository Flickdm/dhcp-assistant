#!/usr/bin/env bash

declare -a adapters
declare -i choice

# Location of config file
declare -r dhcp_config="./udhcpd.conf"

# List of required installed programs
declare -a required_programs=("udhcpd")

#config file
declare -r conf="
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
"

# Capture Ctrl-C
trap ctrlC INT

###############################################################################
# FUNCTION: checkInstall
# DESCRIPTION: checks for applications and for config file
###############################################################################
function checkInstall() {

    install_choice="y"
    for program in ${required_programs[@]}; do
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


    # If config doesn't exist install it
    if [ ! -f ${dhcp_config} ]; then
        touch ${dhcp_config}
        > ${dhcp_config}

        echo -e "$conf" >> ${dhcp_config}
    fi

}

###############################################################################
# FUNCTION: uninstall
# DESCRIPTION: remove the config script and attempt uninstall of programs
###############################################################################
function uninstall() {

    # Remove config
    rm ${dhcp_config}

    # Uninstall programs
    uninstall_choice="y"
    for program in ${required_programs[@]}; do
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
    adapters=($(ls "/sys/class/net"))

    id=0
    for adapter in ${adapters[*]}; do
        printf "\t[%d] %s\n" ${id} ${adapter}
        let id=$id+1
    done

    printf "\n"
    printf "Default: ${adapters[0]}\n"
    read -p "Choice: " choice

    #Set Default to 0
    choice=${choice:0}
}

###############################################################################
# FUNCTION: ctrlFirewall
# DESCRIPTION: opens and allows traffic through firewall for dhcp
###############################################################################
function ctrlFirewall() {
    # 67 : dhcp
    ufw $1 67/udp
    ufw reload
    ufw status
}


###############################################################################
# FUNCTION: ctrlC
# DESCRIPTION: captures the ctrl_c from user to begin cleanup
###############################################################################
function ctrlC() {
    ctrlFirewall "deny"
    ctrlDhcp "stop"
    exit
}

###############################################################################
# FUNCTION: ctrlDhcp
# DESCRIPTION: checks for applications and for config file
###############################################################################
function ctrlDhcp() {

    adapter=${adapters[choice]}

    if [ $1 == "start" ]; then
        # configure interface
        ifconfig ${adapter} 172.168.10.1 netmask 255.255.255.0 broadcast 172.168.10.255 up

        # Start the DHCP Server Process once the Interface is Ready with the IP Add
        udhcpd ${dhcp_config} -f
    elif [ $1 == "stop" ]; then
        # kill dhcp client
        if [ -f /var/run/udhcpc.${adapter}.pid ]; then
            kill `cat /var/run/udhcpc.${adapter}.pid`
        fi
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
# FUNCTION: handleUsage
# DESCRIPTION: handle arguments
###############################################################################
function handleUsage() {

    while getopts ":uh" opt; do
        case ${opt} in
            u )
                uninstall
                exit;
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

    handleUsage "$@"

    #Check to make sure everything is installed
    checkInstall

    choice=0
    #Get user input
    menu

    # Allow the firewall
    ctrlFirewall "allow"

    adapter=${adapters[choice]}
    # updated config with option
    sed -i "s/interface.*/interface ${adapter}/g" "${dhcp_config}" >> "${dhcp_config}"

    ctrlDhcp "stop"
    ctrlDhcp "start"
   }

#pass all arguments
main "$@"
