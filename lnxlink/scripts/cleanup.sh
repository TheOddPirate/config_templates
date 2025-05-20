#!/bin/bash

set -e

echo "🧼 Starter opprydding..."

# Krever sudo
if [[ "$EUID" -ne 0 ]]; then
  echo "Vennligst kjør scriptet med sudo"
  exit 1
fi

# 🔄 Oppdaterer systemet
echo "🔄 Oppdaterer pakker..."
apt-get update -qq
apt-get upgrade -y -qq  > /dev/null 2>&1 

# Finner rot-partisjonen
DISK="/"
SPACE_BEFORE=$(df --output=avail "$DISK" | tail -1 | tr -d ' ')
echo "💾 Ledig plass før: $(df -h "$DISK" | awk 'NR==2{print $4}')"

echo "1. Rydder apt-cache..."
apt-get clean -qq  > /dev/null 2>&1 
apt-get autoclean -qq > /dev/null 2>&1 
apt-get autoremove -y -qq > /dev/null 2>&1 

echo "2. Sletter gamle kjernefiler..."
dpkg -l 'linux-image-*' | awk '/^ii/{ print $2}' | grep -v "$(uname -r | cut -d '-' -f1,2)" | xargs apt-get -y purge > /dev/null 2>&1 || true

echo "3. Tømmer journal logs (beholder 3 dager)..."
journalctl --vacuum-time=3d -q > /dev/null

echo "4. Tømmer midlertidige kataloger..."
rm -rf /tmp/* /var/tmp/* > /dev/null 2>&1

echo "5. Sletter gamle loggfiler (>7 dager)..."
find /var/log -type f -name "*.log" -mtime +7 -exec rm -f {} \; > /dev/null 2>&1

echo "6. Tømmer papirkurver..."
for u in /home/*; do
  rm -rf "$u/.local/share/Trash/files/"* > /dev/null 2>&1
done
rm -rf /root/.local/share/Trash/files/* > /dev/null 2>&1

echo "7. Fjerner gamle Snap-versjoner..."
snap list --all 2>/dev/null | awk '/disabled/{print $1, $3}' | while read snapname revision; do
  snap remove "$snapname" --revision="$revision" > /dev/null 2>&1
done

echo "8. Fjerner oversatte man-sider..."
rm -rf /usr/share/man/?? /usr/share/man/??_* > /dev/null 2>&1

echo "9. Kjører deborphan for foreldreløse pakker..."
if ! command -v deborphan &> /dev/null; then
  read -t 30 -rp "❓ 'deborphan' er ikke installert. Vil du installere det? [y/N] (30 sek timeout): " REPLY || REPLY="n"
  if [[ "$REPLY" =~ ^[Yy]$ ]]; then
    echo "📦 Installerer debortphan....."
    apt-get install -y deborphan > /dev/null 2>&1
  else
    echo "⚠️  Hopper over deborphan-opprydding."
  fi
fi

if command -v deborphan &> /dev/null; then
  for i in {1..5}; do
    orphaned=$(deborphan)
    if [[ -z "$orphaned" ]]; then
      break
    fi
    echo "$orphaned" | xargs apt-get -y remove --purge > /dev/null 2>&1
  done
fi

echo "10. Renser opp i Docker..."
docker system prune -af > /dev/null 2>&1

# 📊 Oppsummering
SPACE_AFTER=$(df --output=avail "$DISK" | tail -1 | tr -d ' ')
SPACE_FREED_KB=$((SPACE_AFTER - SPACE_BEFORE))
SPACE_FREED_HUMAN=$(numfmt --to=iec $((SPACE_FREED_KB * 1024)))

echo "✅ Ferdig med opprydding!"
echo "💾 Ledig plass etter: $(df -h "$DISK" | awk 'NR==2{print $4}')"
echo "🧹 Frigjort plass: $SPACE_FREED_HUMAN"
