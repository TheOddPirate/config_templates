#!/bin/bash

WEBHOOK_URL="http://192.168.86.2:8123/api/webhook/-S0EJFKb0H5LqaCXtQUXi5t6b"
HOSTNAME=$(hostname)
ALERT_SENT=0

echo "🧪 Kjører SMART-sjekk på disker..."

if ! command -v smartctl &> /dev/null; then
  read -t 30 -rp "❓ 'smartmontools' er ikke installert. Vil du installere det? [y/N] (30 sek timeout): " REPLY || REPLY="n"
  if [[ "$REPLY" =~ ^[Yy]$ ]]; then
    echo "📦 Installerer smartmontools..."
    apt-get update -qq && apt-get install -y smartmontools > /dev/null 2>&1
  else
    echo "⚠️  Avslutter – smartmontools er nødvendig."
    exit 1
  fi
fi

for DISK in $(lsblk -dn -o NAME | grep -E '^sd|^nvme'); do
  DEV="/dev/$DISK"

  if smartctl -i "$DEV" | grep -q "SMART support is: Enabled"; then
    MOUNTPOINT=$(lsblk -no MOUNTPOINT "$DEV" | grep -v "^$" | head -n1)

    if [[ "$MOUNTPOINT" == "/media/Series/Disk3" ]]; then
      echo "⏭️ Hopper over $DEV (montert på $MOUNTPOINT)"
      continue
    fi
    OUTPUT=$(smartctl -H -A -q silent "$DEV")
    HEALTH=$(echo "$OUTPUT" | grep -E "SMART.*(health|status)" || true)

    if echo "$HEALTH" | grep -qi "FAIL\|BAD"; then
      ALERT_SENT=1
      MOUNTPOINT=$(lsblk -no MOUNTPOINT "$DEV" | grep -v "^$" | head -n1)
      MOUNTPOINT=${MOUNTPOINT:-"ikke mountet"}

      curl -s -X POST -H "Content-Type: application/json" \
        -d "{
              \"host\": \"$HOSTNAME\",
              \"disk\": \"$DEV\",
              \"mountpoint\": \"$MOUNTPOINT\",
              \"status\": \"${HEALTH//\"/\\\"}\"
            }" "$WEBHOOK_URL"
    fi
  fi
done

if [[ $ALERT_SENT -eq 0 ]]; then
  echo "✅ Alle disker ser OK ut."
fi
