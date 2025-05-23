#!/bin/bash
# Default server setup script for new installations
# Installs and configures essential services and tools

set -e

USERNAME=$USER
read -t 30 -p "Hello $USERNAME, do you want to keep this username or set a custom one? It will be used to choose install paths for configurations: " -e -i "$USERNAME" USERNAME
read -p "Hello $USERNAME, please enter the password for your Samba user: " SAMBA_PASS

LNXLINK_DIR="/home/$USERNAME/lnxlink"
SCRIPT_DIR="$LNXLINK_DIR/scripts"
CONFIG_URL="https://github.com/TheOddPirate/config_templates/raw/main/lnxlink/config.yml"
CLEANUP_URL="https://github.com/TheOddPirate/config_templates/raw/main/lnxlink/scripts/cleanup.sh"
DISK_CHECK_URL="https://github.com/TheOddPirate/config_templates/raw/main/lnxlink/scripts/disk_checker.sh"
OFFLINE_CHECKER_URL="https://github.com/TheOddPirate/config_templates/raw/main/lnxlink/scripts/offline_checker.sh"

# MQTT configuration
echo "Now we need some information about your MQTT setup."
MQTT_IP="homeassistant.local"
read -t 30 -p "MQTT IP address (default: $MQTT_IP): " -e -i "$MQTT_IP" MQTT_IP
MQTT_PORT=1883
read -t 30 -p "MQTT port (default: $MQTT_PORT): " -e -i "$MQTT_PORT" MQTT_PORT
read -p "MQTT username: " MQTT_USER
read -p "MQTT password: " MQTT_PASS

# Home Assistant configuration
echo "Now we need some information about your Home Assistant setup."
HASS_URL="http://homeassistant.local:8123"
read -t 30 -p "Home Assistant URL (default: $HASS_URL): " -e -i "$HASS_URL" HASS_URL
read -p "Home Assistant API token: " API_TOKEN

# Timezone configuration
TIMEZONE=$(timedatectl show --property=Timezone --value)
read -t 30 -p "Timezone (default: $TIMEZONE): " -e -i "$TIMEZONE" TIMEZONE

# CrowdSec configuration
echo "Now we need some information about your CrowdSec setup."
read -p "CrowdSec enrollment key: " CROWDSEC_KEY
CROWDSEC_ENROLL="sudo cscli console enroll -e context $CROWDSEC_KEY"


#Swapfile
CURRENT_SWAP_SIZE=$(sudo swapon --show | awk '/file/ {print $3}')
CURRENT_SWAP_SIZE_MB=$(echo "$CURRENT_SWAP_SIZE" / 1024 | bc)
DESIRED_SWAP_SIZE=$CURRENT_SWAP_SIZE_MB
SWAP_PATH=$(swapon --show | awk 'NR==2{print $1}')
read -t 30 -p "Do you want a custom swapfile size or keep the current? (default: $CURRENT_SWAP_SIZE_MB MB): " -e -i "$CURRENT_SWAP_SIZE_MB" DESIRED_SWAP_SIZE

if [ ! -f $SWAP_PATH ]; then
    SWAP_PATH="/swamp.img"
fi

# Function to check if a command is installed
is_installed() {
    command -v "$1" > /dev/null 2>&1
}

echo ">> Updating system..."
sudo apt-get update -qq  > /dev/null  && sudo apt-get upgrade -y -qq  > /dev/null 

echo ">> Setting timezone to $TIMEZONE..."
sudo timedatectl set-timezone "$TIMEZONE"

if ! is_installed unattended-upgrades; then
    echo ">> Installing unattended-upgrades..."
    sudo apt-get install -y unattended-upgrades  > /dev/null 
    sudo dpkg-reconfigure -f noninteractive unattended-upgrades  > /dev/null 
fi

echo ">> Creating necessary directories..."
sudo mkdir -p /Docker /media  > /dev/null 
sudo chown -R "$USERNAME:$USERNAME" /Docker /media  > /dev/null 

if ! is_installed smbd; then
    echo ">> Installing Samba..."
    sudo apt-get install -y samba  > /dev/null 
    (echo "$SAMBA_PASS"; echo "$SAMBA_PASS") | sudo smbpasswd -s -a "$USERNAME"

    for share in Docker media Home; do
        if ! grep -q "^\[$share\]" /etc/samba/smb.conf; then
            echo ">> Adding $share share to Samba configuration..."
            case $share in
                Docker)
                    path="/Docker"
                    ;;
                media)
                    path="/media"
                    ;;
                Home)
                    path="/home/$USERNAME"
                    ;;
            esac
            sudo tee -a /etc/samba/smb.conf > /dev/null <<EOL
[$share]
   path = $path
   browseable = yes
   read only = no
   guest ok = yes
   force user = $USERNAME
EOL
        else
            echo ">> $share share already exists in Samba configuration."
        fi
    done
    sudo systemctl restart smbd nmbd
fi

if ! is_installed wsdd; then
    echo ">> Installing wsdd..."
    sudo apt-get install -y wsdd
    if [ ! -f "/etc/systemd/system/wsdd.service" ]; then
        echo ">> Creating wsdd systemd service..."
        sudo tee /etc/systemd/system/wsdd.service > /dev/null <<EOL
[Unit]
Description=Web Services Dynamic Discovery host daemon
After=network.target

[Service]
Type=simple
ExecStart=/usr/bin/wsdd -4

[Install]
WantedBy=multi-user.target
EOL
        sudo systemctl daemon-reload
    fi
    sudo systemctl enable --now wsdd.service
fi

if ! is_installed docker; then
    echo ">> Installing Docker..."
    for pkg in docker.io docker-doc docker-compose docker-compose-v2 podman-docker containerd runc; do
        sudo apt-get remove -y "$pkg" > /dev/null 
    done
    curl -fsSL https://get.docker.com | sudo bash
    sudo usermod -aG docker "$USERNAME"  > /dev/null 
fi

for pkg in deborphan smartctl pipx; do
    if ! is_installed "$pkg"; then
        echo ">> Installing $pkg..."
        sudo apt-get install -y "$pkg"  > /dev/null 
    fi
done

if ! is_installed conda; then
    if [ ! -d "/home/$USERNAME/miniconda" ]; then
        echo ">> Installing Miniconda..."
        curl -sS https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh -o miniconda.sh > /dev/null 
        bash miniconda.sh -b -p "/home/$USERNAME/miniconda"  > /dev/null 
        echo "export PATH=/home/$USERNAME/miniconda/bin:\$PATH" >> "/home/$USERNAME/.bashrc"
        source "/home/$USERNAME/.bashrc" 
        rm miniconda.sh  > /dev/null 
    fi
fi

if [ ! -f "$LNXLINK_DIR/config.yml" ]; then
    echo ">> Setting up lnxlink configuration..."
    mkdir -p "$SCRIPT_DIR"  > /dev/null 
    chown -R "$USERNAME:$USERNAME" "$LNXLINK_DIR"  > /dev/null 

    wget -qO "$LNXLINK_DIR/config.yml" "$CONFIG_URL"  > /dev/null 

    HOSTNAME=$(hostname)
    sed -i "s/{server-name}/Server-$HOSTNAME/g" "$LNXLINK_DIR/config.yml"
    sed -i "s|{mqttusername}|$MQTT_USER|g" "$LNXLINK_DIR/config.yml"
    sed -i "s|{mqttip}|$MQTT_IP|g" "$LNXLINK_DIR/config.yml"
    sed -i "s|{mqttport}|$MQTT_PORT|g" "$LNXLINK_DIR/config.yml"
    sed -i "s|{mqqpassword}|$MQTT_PASS|g" "$LNXLINK_DIR/config.yml"
    sed -i "s|{hassurl}|$HASS_URL|g" "$LNXLINK_DIR/config.yml"
    sed -i "s|{apitoken}|$API_TOKEN|g" "$LNXLINK_DIR/config.yml"
    sed -i "s|{current_user}|$USERNAME|g" "$LNXLINK_DIR/config.yml"

    echo ">> Downloading lnxlink scripts..."
    wget -qO "$SCRIPT_DIR/cleanup.sh" "$CLEANUP_URL"
    wget -qO "$SCRIPT_DIR/disk_checker.sh" "$DISK_CHECK_URL"
    wget -qO "$SCRIPT_DIR/offline_checker.sh" "$OFFLINE_CHECKER_URL"

    chmod +x "$SCRIPT_DIR/"*.sh  > /dev/null 

    echo ">> Installing lnxlink..."
    curl -fsSL https://raw.githubusercontent.com/bkbilly/lnxlink/master/install.sh | bash  > /dev/null 
fi

if ! is_installed cscli; then
    echo ">> Installing CrowdSec and firewall bouncer..."
    curl -s https://packagecloud.io/install/repositories/crowdsec/crowdsec/script.deb.sh | sudo bash  > /dev/null 
    sudo apt-get install -y crowdsec crowdsec-firewall-bouncer-nftables  > /dev/null 
    $CROWDSEC_ENROLL

    echo ">> Generating IP whitelist..."
    PUB_IPV4=$(curl -s https://checkip.amazonaws.com)
    PUB_IPV6=$(curl -s https://ipecho.net/plain)
    PRIV_IPV4=$(ip addr show | awk '$1 == "inet" { print $2 }' | cut -d/ -f1 | grep -vE '^127\.|^172\.' | sed -E 's/^([0-9]+\.[0-9]+)\.[0-9]+\.[0-9]+$/- \1.*.*/' | sed 's|$|/24|')

    sudo tee /etc/crowdsec/parsers/s02-enrich/local-whitelist.yaml > /dev/null <<EOL
whitelist:
  reason: "Local and personal trusted IP ranges"
  ip:
$PRIV_IPV4
    - "$PUB_IPV4/32"
    - "$PUB_IPV6/128"
EOL

    sudo systemctl restart crowdsec  > /dev/null 
fi

echo ">> Configuring log rotation and limiting journald to 7 days..."
sudo journalctl -q --vacuum-time=7d

if is_installed snap; then
    echo ">> Removing Snap and snapd..."
    sudo snap remove --purge $(snap list | awk 'NR>1 {print $1}') || true
    sudo apt-get purge -y snapd  > /dev/null 
fi

for pkg in htop ncdu iotop; do
    if ! is_installed "$pkg"; then
        echo ">> Installing $pkg..."
        sudo apt-get install -y "$pkg"  > /dev/null 
    fi
done
if ! is_installed zramctl; then
    echo ">> Installing  zram-tools..."
    sudo apt-get install -y  zram-tools   > /dev/null 
fi


if CURRENT_SWAP_SIZE_MB != DESIRED_SWAP_SIZE; then
    # Check if swapfile exists
    echo "Fixing your swapfile size"
    if [ -f $SWAP_PATH ]; then
        echo "Swapfile exists. Current size: $CURRENT_SWAP_SIZE_MB MB"
        # Disable swap
        sudo swapoff $SWAP_PATH
        # Resize swapfile
        sudo dd if=/dev/zero of=$SWAP_PATH bs=1M count=$DESIRED_SWAP_SIZE oflag=append conv=notrunc
    	# Set permissions
    	sudo chmod 600 $SWAP_PATH
    	# Initialize swapfile
    	sudo mkswap $SWAP_PATH
    	# Enable swap
    	sudo swapon $SWAP_PATH
    	echo "Swapfile resized to $DESIRED_SWAP_SIZE MB."
    else
    	echo "Swapfile does not exist. Creating new swapfile..."
    	# Create new swapfile
    	sudo dd if=/dev/zero of=$SWAP_PATH bs=1M count=$DESIRED_SWAP_SIZE
    	# Set permissions
    	sudo chmod 600 $SWAP_PATH
    	# Initialize swapfile
    	sudo mkswap $SWAP_PATH 
    	# Enable swap
    	sudo swapon $SWAP_PATH
    	echo "New swapfile created with size $DESIRED_SWAP_SIZE MB."
    fi
fi

echo "✅ Setup complete! Your server is now configured with all services and optimizations."
