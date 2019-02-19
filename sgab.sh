#!/bin/bash
SOURCE="${BASH_SOURCE[0]}"
while [ -h "$SOURCE" ]; do
    DIR="$( cd -P "$( dirname "$SOURCE" )" && pwd )"
    SOURCE="$(readlink "$SOURCE")"
    [[ $SOURCE != /* ]] && SOURCE="$DIR/$SOURCE"
done
DIR="$( cd -P "$( dirname "$SOURCE" )" && pwd )"
cd "$DIR"

export http_proxy=""


# Error codes:
#  1: Invalid argument
# -1: Invalid profile or missing cookies
# -2: Expired cookies
# -3: Connection timed out


# Options
MIN_POINTS=20
RECHARGE_DELAY=1800
DEFAULT_DELAY=300
ONLY_LINUX_GAMES=0
AGENT_STRING="Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/48.0.2564.103 Safari/537.36"

# Variables
PROFILE=""
DELAY=$DEFAULT_DELAY
TROPHY_OLD=0
FAILS_ROW=0
FAILS_MAX=5
PROFANITY_FILTERS_FILE="$DIR/profanity-filters.sed"
COOKIES_FILE=""
LOG_FOLDER="$DIR/logs/"
CACHE_FOLDER="$DIR/cache/"
LOG_ENABLED=0
PROXY_ENABLED=0

set -o errexit -o noclobber -o nounset -o pipefail
PARAMS="$(getopt -o p:l -l profile:,linux --name "$0" -- "$@")"
eval set -- "$PARAMS"

while true
do
    case "$1" in
        -p|--profile)
            PROFILE="$2"
            shift 2
            ;;
        -l|--linux)
            ONLY_LINUX_GAMES=1
            shift
            ;;
        --)
            shift
            break
            ;;
        *)
            echo "Invalid argument: $1" >&2
            exit 1
            ;;
    esac
done

write_message() {
	MESSAGE=$*
	echo $*

	if [ $LOG_ENABLED -eq 1 ]; then
		LOG_FILE="$LOG_FOLDER/log_"$(date +"%Y-%m-%d")".log"
		echo "<"$(date +"%H:%M:%S")">" $* >> $LOG_FILE
	fi
}

send_mail_trophies() {
    TO="Hori873Games@GMail.com"
    SUBJECT=$(echo "SGAB - $PROFILE" | sed -f "$PROFANITY_FILTERS_FILE")
    BODY=$(echo "You have $TROPHY_OLD unclaimed gifts on $PROFILE" | sed -f "$PROFANITY_FILTERS_FILE")

    echo "$BODY" | mail -s "$SUBJECT" "$TO"
    write_message "Mail sent to $TO!"
}

text_to_time() {
    TIME=$(echo "$*" | sed 's/[a-zA-Z]//g' | tr -d ' \t\n\r\f')

    if [ -n "$TIME" ]; then
        if [ $(echo "$*" | grep -c "minute") -ge 1 ]; then
		    TIME=$(($TIME * 60))
	    elif [ $(echo "$*" | grep -c "hour") -ge 1 ]; then
            TIME=$(($TIME * 3600))
	    elif [ $(echo "$*" | grep -c "day") -ge 1 ]; then
            TIME=$(($TIME * 86400))
            write_message "WARNING: Time is measured in days!!!"
        fi
    else
        $TIME=$DEFAULT_DELAY
    fi

    echo $TIME
}

fetch() {
    URL="$1"
    wget -P "$CACHE_FOLDER_PROFILE" -U "$AGENT_STRING" -x -q --load-cookies "$COOKIES_FILE" --keep-session-cookies --save-cookies "$COOKIES_FILE" -T 10 --dns-timeout 10 --tries 3 "$URL"
    
    if [ ! -f "$CACHE_FOLDER_PROFILE/$URL" ]; then
        echo "Page '$URL' could not be fetched"
    fi
}

post_data() {
    URL=$1
    shift
    POSTDATA="$*"
    wget -P "$CACHE_FOLDER_PROFILE" -U "$AGENT_STRING" -q --load-cookies "$COOKIES_FILE" -T 10 --dns-timeout 10 --tries 3 --post-data="$POSTDATA" "$URL"
}


COOKIES_FILE="$DIR/cookies/$PROFILE"
LOG_FOLDER="$DIR/logs/$PROFILE/"
CACHE_FOLDER_PROFILE="$DIR/cache/$PROFILE/"

if [ ! -n "$PROFILE" ]; then
    write_message "FATAL ERROR: No profile selected!"
    exit -1
fi

if [ ! -f "$COOKIES_FILE" ]; then
    write_message "FATAL ERROR: Cookie file not present!"
    exit -1
fi

if [ $LOG_ENABLED == 1 ]; then
    if [ ! -d "$LOG_FOLDER" ]; then
	    mkdir -p "$LOG_FOLDER"
    fi
fi

if [ ! -d "$CACHE_FOLDER" ]; then
    mkdir -p "$CACHE_FOLDER"
fi

if [ $(cat proxies.txt | grep "^$PROFILE=" -c) -ge 1 ]; then
    LINE=$(cat proxies.txt | grep "^$PROFILE=" | tail -1)

    export http_proxy=$(echo "$LINE" | awk -F= '{ print $2 }')
    if [ -n "http_proxy" ]; then
        PROXY_ENABLED=1
    fi
fi

write_message "Started SteamGifts-AutoBot"
write_message "Selected profile:" $PROFILE

if [ $ONLY_LINUX_GAMES == 1 ]; then
    write_message "Only taking Linux games"
fi

if [ $PROXY_ENABLED == 1 ]; then
    write_message "Proxy enabled: $http_proxy"
fi

while true; do
    DELAY=$DEFAULT_DELAY
    if [ -d "$CACHE_FOLDER_PROFILE" ]; then
        rm -rf "$CACHE_FOLDER_PROFILE"
    fi

    echo "Determining IP adress..."
    IP=$(sh "get-ip.sh")

    if [ ! -n "$IP" ]; then
        FAILS_ROW=$(($FAILS_ROW+1))
        write_message "Connection failed... ($FAILS_ROW)"

        if [ $FAILS_ROW -ge $FAILS_MAX ]; then
            write_message "Max connection fail limit reached. Exiting..."
            exit -3
        else
            sleep 10
            continue
        fi
    else
        FAILS_ROW=0
    fi

    write_message "Downloading index.html... (IP is: $IP)"
    fetch "http://www.steamgifts.com/"

    HTML_INDEX="$CACHE_FOLDER_PROFILE/www.steamgifts.com/index.html"

    if [ ! -f "$HTML_INDEX" ]; then
        # Check wether the cookies are still valid
        if [ $(grep -c "Sign in through STEAM" $HTML_INDEX) -eq 0 ]; then
            write_message "The cookies have expired, please update them!"
            exit -2
        fi

        PTS=$(python xpath.py $HTML_INDEX '/html/body/header/nav/div[2]/div[4]/a/span[1]/text()')
        TROPHY=$(python xpath.py $HTML_INDEX '/html/body/header/nav/div[2]/div[2]/a/div/text()')

        if [ -n "$TROPHY" ]; then
            write_message "[ ! ! ! ] You have $TROPHY unclaimed gifts"

            # TODO: Improve this - currently if a gift is claimed and another one immediately won, it won't notice the change
            if [ "$TROPHY" != "$TROPHY_OLD" ]; then
                TROPHY_OLD=$TROPHY
                send_mail_trophies
            fi
        fi

        if [ $PTS -lt $MIN_POINTS ]; then
            write_message "Points are less than $MIN_POINTS"
            DELAY=$RECHARGE_DELAY
        else
            write_message "You have $PTS points"

            GA_LINK=$(python xpath.py "$HTML_INDEX" '/html/body/div[3]/div/div/div/div[2]/div[3]/div[1]/div/div/h2/a[1]/@href')
            GA_GAME=$(python xpath.py "$HTML_INDEX" '/html/body/div[3]/div/div/div/div[2]/div[3]/div[1]/div/div/h2/a[1]/@value')
            
            # TODO: This is an ugly hotfix - Can it be removed now? Can it be rewritten properly?
            if [ "$GA_LINK" == "" ]; then
                GA_LINK=$(python xpath.py "$HTML_INDEX" '/html/body/div[3]/div/div/div[2]/div[3]/div[1]/div/div/h2/a[1]/@href')
                GA_LINK=$(python xpath.py "$HTML_INDEX" '/html/body/div[3]/div/div/div[2]/div[3]/div[1]/div/div/h2/a[1]/@value')
		    fi

            GA_CODE=$(echo $GA_LINK | awk -F/ '{print $3}')
		    #GA_GAME=$(echo $GA_LINK | awk -F/ '{print $4}' | sed -e "s/\b\(.\)/\u\1/g" | sed "s/-/\ /g")
            HTML_GA="$CACHE_FOLDER_PROFILE/www.steamgifts.com$GA_LINK"

            write_message "Validating first listed giveaway: $GA_CODE ([$STEAM_APPID] $GA_GAME)"

            # Check if game supports Linux
            if [ $ONLY_LINUX_GAMES = 1 ]; then            
                STEAM_LINK=$(python xpath.py "$HTML_INDEX" '/html/body/div[3]/div/div/div[2]/div[3]/div[1]/div/div/h2/a[2]/@href')
                STEAM_APPID=$(echo $STEAM_LINK | awk -F/ '{print $5}')
                GA_LINUX=-1
                
                # From cache
                if [ -f "$CACHE_FOLDER/linux-games.txt" ]; then
                    if [ $(cat "$CACHE_FOLDER/linux-games.txt" | grep "$STEAM_APPID" -c) -ge 1 ]; then
                        GA_LINUX=$(cat "$CACHE_FOLDER/linux-games.txt" | grep "$STEAM_APPID" | tail -1 | awk -F= '{print $2}')
                    fi
                # From website
                else
                    GA_LINUX=0 # We start by assuming it does not - It helps in case the webpage fails to be fetched
                    HTML_STEAMDB="$CACHE_FOLDER_PROFILE/steamdb.info/app/$STEAM_APPID/index.html"

                    write_message "Fetching game information..."
                    fetch "https://steamdb.info/app/$STEAM_APPID/"

                    if [ -f "$HTML_STEAMDB" ]; then
                        LINUX=$(python xpath.py $HTML_STEAMDB "//*[contains(concat(' ', normalize-space(@aria-label), ' '), ' Linux ')]")
                        if [ -n "$LINUX" ]; then
                            GA_LINUX=1
                        fi

                        printf "$STEAM_APPID=$GA_LINUX\n" >> "$CACHE_FOLDER/linux-games.txt"
                        sort "$CACHE_FOLDER/linux-games.txt" -o "$CACHE_FOLDER/linux-games.txt"
                    fi
                fi
            fi

            if [ "$ONLY_LINUX_GAMES" == "0" ] || [ "$GA_LINUX" == "1" ]; then
                fetch "http://www.steamgifts.com/$GA_LINK"

                # Giveaway entry logic
	            if [ -f $HTML_GA ]; then
		            if [ $(grep class=\"sidebar__entry-insert\" $HTML_GA -c) -ge 1 ]; then
                        TOKEN=$(python xpath.py $HTML_GA '/html/body/div[2]/div/div/div[1]/form/input[1]/@value')
               		    DO="entry_insert"

				        write_message "Entering this giveaway ($GA_CODE)..."
			            post_data "http://www.steamgifts.com/ajax.php" "xsrf_token=$TOKEN&do=$DO&code=$GA_CODE"

                        # Comment posting logic
			            if [ -f "comments.txt" ]; then
		            	    TOKEN=$(python xpath.py $HTML_GA '/html/body/div[2]/div/div/div[2]/*/div/div/div[2]/div/form/input[2]/@value')
			                DO="comment_new"
				            DESCRIPTION=$(shuf -n 1 comments.txt)

					        write_message "Sending a comment (\"$DESCRIPTION\")..."
                            post_data "www.steamgifts.com$GA_LINK" "do=$DO&xsrf_token=$TOKEN&description=$DESCRIPTION"
                        fi
                    else
                        write_message "Can't enter this giveaway"
                        # TODO: Show reason why - take it exactly as it is in the html
                    fi

                    TIME_TEXT=$(python xpath.py $HTML_GA '/html/body/div[1]/div/div/div/div[2]/div[1]/span/text()')
                    DELAY=$(echo $TIME_TEXT | sed 's/[a-zA-Z]//g' | tr -d ' \t\n\r\f')

            	    if [ $(echo "$TIME_TEXT" | grep -c "Ended") == 0 ]; then
                        DELAY=$(text_to_time "$TIME_TEXT")
                    else
                        DELAY=1
                    fi
		        fi
            else
                TIME_TEXT=$(python xpath.py $HTML_INDEX '/html/body/div[3]/div/div/div[2]/div[3]/div[1]/div/div/div[1]/div[1]/span/text()')
                DELAY=$(text_to_time "$TIME_TEXT")

                write_message "This game does not support Linux"
            fi
	    fi
    fi
    
    write_message "Waiting $DELAY seconds..."
 	sleep $DELAY
done

