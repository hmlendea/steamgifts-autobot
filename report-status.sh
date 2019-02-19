ACCOUNTS_TOTAL=0
ACCOUNTS_ACTIVE=0
LINES_TO_SHOW=3
VERBOSITY=2

while getopts "snla" OPT; do
    case "$OPT" in
        s)
            VERBOSITY=1
            ;;
        n)
            VERBOSITY=2
            ;;
        l)
            VERBOSITY=3
            ;;
        a)
            VERBOSITY=4
            ;;
    esac
done
shift $((OPTIND-1))
[ "$1" = "--" ] && shift

function print_status {
    ACCOUNTS_TOTAL=$(($ACCOUNTS_TOTAL+1))

    STATUS=$(systemctl status sgab@$1 | grep "Active:" | awk '{ print $2 }')

    if [ "$STATUS" == "active" ]; then
        ACCOUNTS_ACTIVE=$(($ACCOUNTS_ACTIVE+1))
        STATUS="$(tput bold)$(tput setaf 2)active$(tput sgr0)"
    else
        STATUS="$(tput bold)$(tput setaf 1)inactive$(tput sgr0)"
    fi

    echo "SteamGifts AutoBot for $(tput bold)$(tput setaf 3)$1$(tput sgr0) is $(tput bold)$STATUS$(tput sgr0)"

    if [ $VERBOSITY == 2 ]; then
        systemctl status sgab@$1 | grep "sgab.sh" | tail -$LINES_TO_SHOW
    elif [ $VERBOSITY == 3 ]; then
        systemctl status sgab@$1 | tail -15
    elif [ $VERBOSITY == 4 ]; then
        systemctl status sgab@$1 -l
    fi

#    if [ $VERBOSITY != 1 ]; then
#        echo -e ""
#    fi
}

echo -e "Status report of all enabled accounts\n"

for ENABLED_ACCOUNT in $(ls /etc/systemd/system/multi-user.target.wants | grep sgab | sed 's/^sgab@//g' | sed 's/.service$//g'); do
    print_status $ENABLED_ACCOUNT
done

echo -e "\nActive accounts: $(tput bold)$(tput setaf 6)$ACCOUNTS_ACTIVE/$ACCOUNTS_TOTAL$(tput sgr0)"
