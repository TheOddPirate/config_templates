#!/bin/bash
# Having some problems with my google nest repeaters going offline,
# this script was made to check if the mac is found on my network and
# trigger a execution in home assistant to restart the sockets if its offline
# Repeater MAC-adresser
declare -A REPEATERS
REPEATERS["Kjokkenet"]="e4:5e:1b:8f:19:08"
REPEATERS["Gangen"]="e4:5e:1b:7f:5e:20"

# Webhook base
WEBHOOK_BASE="http://192.168.86.2:8123/api/webhook"
# Eks: https://home.duckdns.org/api/webhook/repeater_kjokkenet_offline


# Sjekk at arp-scan er installert
if ! command -v arp-scan &> /dev/null; then
    echo "arp-scan ikke funnet. Installerer..."
    if [ -f /etc/debian_version ]; then
        sudo apt-get update && sudo apt-get install -y arp-scan
    else
        echo "Ukjent system – installer arp-scan manuelt."
        exit 1
    fi
fi

# Søk etter MAC i nettverket
for NAME in "${!REPEATERS[@]}"; do
    MAC=${REPEATERS[$NAME]}
    IP=$(arp-scan --localnet --interface=enp1s0 | grep "$MAC" | awk '{print $1}')

    if [ -z "$IP" ]; then
        echo "$NAME er OFFLINE"
	echo "$WEBHOOK_BASE/repeater_${NAME}_offline"
        curl -s -X POST "$WEBHOOK_BASE/repeater_${NAME}_offline"
    else
        echo "$NAME er ONLINE - $IP"
    fi
done
