#!/bin/bash
# So this is more or less my default setup script for every new server i install
# It makes sure all the default crap i need is installed 
#
# The script starts by asking you to give some variables
# Updates the server
# Sets the timezone
# Installs and sets up unnatended upgrades
# makes sure my default folders exists and chown to my user "/Docker" and "/media"
# Installs samba and sets the password you choose on the user you choose
# makes sure "/Docker" , "/media", "/home/username" is shared over samba
# Installs wsdd as a service so the shares is auto discovered on my network
# Installs docker and ands the user to the docker group
# Installs deborphan , pipx , smartmontools, miniconda 
# Installs lnxlink and downloads my config and scripts from this repository
# the active window module is not downloaded as i dont use a DE on my servers
# you will need to manually start lnxlink the first time with the config file saved in 
# "/home/USERNAME/lnxlink/config.yml"
# to activate the service "lnxlink -c /home/USERNAME/lnxlink/config.yml" and maybe -s in the command? i dont remember =(
#
# Installs crowdsec and bouncer, creates a whitelist with local ip ranges and public ipv4 and ipv6 adresses
# enrolls your crowdsec install
#
# configures logrotate to 7 days
# Removes snap from the server
# Installs some more tools
# zram-tools , htop , ncdu , iotop
set -e

USERNAME=$USER
read -t 30 -p "Hello $USERNAME, do you want to keep this username or set a custom one? it will be used to choose install paths for stuff" -e -i "$USERNAME" USERNAME
read -p "Hello $USERNAME, what password do you want on your samba user? " SAMBA_PASS
LNXLINK_DIR="/home/$USERNAME/lnxlink"
SCRIPT_DIR="$LNXLINK_DIR/scripts"
CONFIG_URL="https://github.com/TheOddPirate/config_templates/raw/refs/heads/main/lnxlink/config.yml"
CLEANUP_URL="https://github.com/TheOddPirate/config_templates/blob/510b2181954e2ff11a0c3f0448011d14effe94a0/lnxlink/scripts/cleanup.sh"
DISK_CHECK_URL="https://github.com/TheOddPirate/config_templates/blob/510b2181954e2ff11a0c3f0448011d14effe94a0/lnxlink/scripts/disk_checker.sh"
OFFLINE_CHECKER_URL="https://github.com/TheOddPirate/config_templates/blob/510b2181954e2ff11a0c3f0448011d14effe94a0/lnxlink/scripts/offline_checker.sh"
#Mqtt info grabbing
echo "Now we need some information about your mqtt setup"
MQQ_IP="homeassistan.local"
read -t 30 -p "Hello $USERNAME, do you want to set a custom mqtt ip or keep the homeassistant default hostname?" -e -i "$MQQ_IP" MQQ_IP
MQQ_PORT=1883
read -t 30 -p "Hello $USERNAME, do you want to set a custom mqtt port or keep the default?" -e -i "$MQQ_PORT" MQQ_PORT
read -p "Hello $USERNAME, what is the port of your mqtt setup? " MQQ_PORT
read -p "Hello $USERNAME, what is the username of your mqtt setup? " MQTT_USER
read -p "Hello $USERNAME, what is the password of your mqtt setup? " MQQ_PASS

#HASS info grabbing
echo "Now we need some information about your home assistant setup"
HASS_URL="http://homeassistant.local:8123"
read -t 30 -p "Hello $USERNAME, do you want to set a custom homeassistant url or keep the default? " -e -i "$HASS_URL" HASS_URL
read -p "Hello $USERNAME, what api token you use for home assistant?" API_TOKEN

TIMEZONE=$(find /usr/share/zoneinfo -type f ! -regex ".*/Etc/.*" -exec cmp -s {} /etc/localtime \; -print | sed -e 's@.*/zoneinfo/@@' | head -n1)
read -t 30 -p "Do you want to keep this timezone or change to something else? $USERNAME  " -e -i "$TIMEZONE" TIMEZONE
#Crowdsec info grabbing?
echo "Now we need some info about your crowdsek setup"
read -p "Hello $USERNAME, what is your crowdsek enrollment key?" CROWDSEK_KEY
CROWDSEC_ENROLL="sudo cscli console enroll -e context $CROWDSEK_KEY"

is_installed() {
    command -v "$1" > /dev/null 2>&1
}

echo ">> Oppdaterer systemet..."
sudo apt-get update > /dev/null && sudo apt-get upgrade -y > /dev/null

echo ">> Setter tidssone til $TIMEZONE..."
sudo timedatectl set-timezone $TIMEZONE > /dev/null

if ! is_installed unattended-upgrades; then
    echo ">> Aktiverer automatiske sikkerhetsoppdateringer..."
    sudo apt-get install -y unattended-upgrades > /dev/null
    sudo dpkg-reconfigure -f noninteractive unattended-upgrades > /dev/null
fi 

 if [ ! -d "/Docker/" ]; then
    echo ">> Lager nødvendige mapper..."
    sudo mkdir -p /Docker /media > /dev/null
    sudo chown -R "$USERNAME:$USERNAME" /Docker /media  > /dev/null
fi

if ! is_installed smbd; then
    echo ">> Installerer og setter opp Samba..."
    sudo apt-get install -y samba > /dev/null
    (echo "$SAMBA_PASS"; echo "$SAMBA_PASS") | sudo smbpasswd -s -a "$USERNAME"
    if grep -q "[Docker]" /etc/samba/smb.conf ; then
        echo "docker share already in samba config"
    else
        sudo tee -a /etc/samba/smb.conf > /dev/null <<EOL
[Docker]
   path = /Docker
   browseable = yes
   read only = no
   guest ok = yes
   force user = $USERNAME
EOL
    fi
    if grep -q "[media]" /etc/samba/smb.conf ; then
        echo "media share already in samba config"
    else
        sudo tee -a /etc/samba/smb.conf > /dev/null <<EOL
[media]
   path = /media
   browseable = yes
   read only = no
   guest ok = yes
   force user = $USERNAME
EOL
    fi    
    if grep -q "[Home]" /etc/samba/smb.conf ; then
        echo "home share already in samba config"
    else
        sudo tee -a /etc/samba/smb.conf > /dev/null <<EOL
[Home]
   path = /home/$USERNAME
   browseable = yes
   read only = no
   guest ok = no
   force user = $USERNAME
EOL
    fi
    sudo systemctl restart smbd nmbd

fi

if ! is_installed wsdd; then
    echo ">> Installerer wsdd..."
    sudo apt-get install -y wsdd  > /dev/null
    if [ ! -f "/etc/systemd/system/wsdd.service " ]; then
        sudo tee  /etc/systemd/system/wsdd.service > /dev/null <<EOL
[Unit]
Description=Web Services Dynamic Discovery host daemon
Requires=multi-user.target
After=multi-user.target

[Service]
Type=simple
ExecStart=/usr/bin/wsdd -4
#User=nobody
#Group=nobody

[Install]
WantedBy=multi-user.target
EOL
        sudo systemctl daemon-reload
    fi
    sudo systemctl enable --now wsdd.service
fi


if ! is_installed docker; then
    echo ">> Installerer Docker..."
    for pkg in docker.io docker-doc docker-compose docker-compose-v2 podman-docker containerd runc; do sudo apt-get remove $pkg;  done
    curl -L https://get.docker.com | sudo bash  > /dev/null
    sudo usermod -aG docker $USERNAME
fi

if ! is_installed deborphan; then
    echo ">> Installerer deborphan..."
    sudo apt-get install -y deborphan   > /dev/null 
fi 

if ! is_installed smartctl; then
    echo ">> Installerer smartmontools..."
    sudo apt-get install -y smartmontools  > /dev/null 
fi 
if ! is_installed pipx; then
    echo ">> Installerer pipx..."
    sudo apt-get install -y pipx > /dev/null 
    pipx ensurepath  > /dev/null 
fi 

if ! is_installed conda; then
    if [ ! -d "/home/$USERNAME/miniconda" ]; then
        echo ">> Installerer conda..."
        curl -sS https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh -o miniconda.sh   > /dev/null 
        bash miniconda.sh -b -p /home/$USERNAME/miniconda  > /dev/null 
        echo "export PATH=/home/$USERNAME/miniconda/bin:\$PATH" >> /home/$USERNAME/.bashrc
        source /home/$USERNAME/.bashrc
        rm miniconda.sh  > /dev/null 
    fi
fi

if ! is_installed lnxlink; then
    if [ ! -f "$LNXLINK_DIR/config.yml" ]; then
        echo ">> Henter og tilpasser lnxlink config..."
        sudo mkdir -p "$LNXLINK_DIR" "$SCRIPT_DIR" > /dev/null
        sudo chown -R "$USERNAME:$USERNAME" "$LNXLINK_DIR" > /dev/null

        wget -O "$LNXLINK_DIR/config.yml" "$CONFIG_URL"  > /dev/null 

        HOSTNAME=$(hostname)
        sed -i "s/{server-name}/Server-$HOSTNAME/g" "$LNXLINK_DIR/config.yml"
        sed -i "s|{mqttusername}|$MQTT_USER|g" "$LNXLINK_DIR/config.yml"
        sed -i "s|{mqttip}|$MQTT_IP|g" "$LNXLINK_DIR/config.yml"
        sed -i "s|{mqttport}|$MQTT_PORT|g" "$LNXLINK_DIR/config.yml"
        sed -i "s|{mqqpassword}|$MQQ_PASS|g" "$LNXLINK_DIR/config.yml"

        sed -i "s|{hassurl}|$HASS_URL|g" "$LNXLINK_DIR/config.yml"
        sed -i "s|{apitoken}|$API_TOKEN|g" "$LNXLINK_DIR/config.yml"
        
        sed -i "s|{current_user}|$USERNAME|g" "$LNXLINK_DIR/config.yml"
		
        echo ">> Laster ned scripts til lnxlink..."
        wget -O "$SCRIPT_DIR/cleanup.sh" "$CLEANUP_URL"  > /dev/null 
        wget -O "$SCRIPT_DIR/disk_checker.sh" "$DISK_CHECK_URL"  > /dev/null 
        wget -O "$SCRIPT_DIR/offline_checker.sh" "$OFFLINE_CHECKER_URL"  > /dev/null 


        chmod +x "$SCRIPT_DIR/"*.sh  > /dev/null 

        echo ">> Installerer lnxlink..."
        curl -L https://raw.githubusercontent.com/bkbilly/lnxlink/master/install.sh | bash > /dev/null
    fi
fi


if ! is_installed crowdsec; then
    echo ">> Installerer CrowdSec og bouncer..."
    curl -s https://packagecloud.io/install/repositories/crowdsec/crowdsec/script.deb.sh | sudo bash   > /dev/null
    sudo apt-get install -y crowdsec crowdsec-firewall-bouncer-nftables  > /dev/null 
    $CROWDSEC_ENROLL  > /dev/null 
    # Check if the directory does not exist
   if [ ! -d "/etc/crowdsec/parsers/s02-enrich/" ]; then
       # Directory does not exist, so create it
       sudo mkdir "/etc/crowdsec/parsers/s02-enrich/"
   fi
   echo ">> Henter offentlig IPv4 og IPv6..."
   PUB_IPV4=$(curl -s https://checkip.amazonaws.com)
   PUB_IPV6=$(curl -s https://ipecho.net/plain)  
   PRIV_IPV4=$(ip addr show  \
  | awk '$1 == "inet" { print $2 }' \
  | cut -d/ -f1 \
  | grep -vE '^127\.|^172\.' \
  | sed -E 's/^([0-9]+\.[0-9]+)\.[0-9]+\.[0-9]+$/- \1.*.*/' \
  | sed 's|$|/24|')
   echo ">> Lager whitelist for IP-er..."
   sudo tee /etc/crowdsec/parsers/s02-enrich/local-whitelist.yaml > /dev/null <<EOL
whitelist:
  reason: "Local and personal trusted IP ranges"
  ip:
    "PRIV_IPV4"
    - "$PUB_IPV4/32"
    - "$PUB_IPV6/128"
EOL
    sudo systemctl restart crowdsec  > /dev/null 
fi






echo ">> Konfigurerer logrotate og begrenser journald til 7 dager..."
sudo journalctl --quiet  --vacuum-time=7d  > /dev/null 

if is_installed snap; then
    echo ">> Fjerner Snap og snapd..."
    sudo snap remove --purge $(snap list | awk 'NR>1 {print $1}') || true
    sudo apt-get purge -y snapd  > /dev/null 
fi

if ! is_installed zramctl ; then
     echo ">> Installerer zram-tools for bedre minnehåndtering..."
     sudo apt-get install -y zram-tools  > /dev/null 
fi

if ! is_installed htop ; then
    echo ">> Installerer htop.."
    sudo apt-get install -y htop ncdu iotop  > /dev/null 
fi
if ! is_installed ncdu ; then
    echo ">> Installerer ncdu..."
    sudo apt-get install -y ncdu  > /dev/null 
fi
if ! is_installed iotop ; then
    echo ">> Installerer iotop.."
    sudo apt-get install -y iotop  > /dev/null 
fi
echo "✅ Ferdig! Serveren er nå ferdig satt opp med alle tjenester og optimaliseringer."
