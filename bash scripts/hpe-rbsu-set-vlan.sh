#### Usage
#
# create a ilo_ips.txt File with all IPs - one IP per Line
#
#

ILO_USERNAME="Administrator"
ILO_PASSWORD="AWESOME1"
VLAN_ID=3097
VLAN_CONTROL="Enabled"



# Function to set BIOS settings
set_bios_settings() {
  ILO_IP="$1"

  echo "Processing ${ILO_IP}..."

  # 1. Get Session Key
  RESPONSE=$(curl -s -k -i -X POST -H "Content-Type: application/json" \
    -d "{\"UserName\":\"${ILO_USERNAME}\", \"Password\":\"${ILO_PASSWORD}\"}" \
    https://${ILO_IP}/redfish/v1/SessionService/Sessions)

  # Extract X-Auth-Token from headers
  SESSION_KEY=$(echo "$RESPONSE" | grep -Fi "X-Auth-Token:" | awk '{print $2}' | tr -d '\r')
  LOCATION_HEADER=$(echo "$RESPONSE" | grep -Fi "Location:" | awk '{print $2}' | tr -d '\r')

  if [ -z "$SESSION_KEY" ]; then
    echo "ERROR: Failed to get session key for ${ILO_IP}. Response: $RESPONSE"
    return 1
  fi

  echo "Session key obtained for ${ILO_IP}: $SESSION_KEY"

  # 2. Patch BIOS Settings
  BIOS_UPDATE_PAYLOAD="{\"VlanControl\":\"${VLAN_CONTROL}\", \"VlanID\":${VLAN_ID}}"
  UPDATE_RESULT=$(curl -s -k -X PATCH -H "Content-Type: application/json" \
    -H "X-Auth-Token: ${SESSION_KEY}" \
    -d "${BIOS_UPDATE_PAYLOAD}" \
    https://${ILO_IP}/redfish/v1/systems/1/bios/settings)

  if [[ "$UPDATE_RESULT" == *"error"* ]]; then
    echo "ERROR: Failed to update BIOS settings for ${ILO_IP}. Response: $UPDATE_RESULT"
    return 1
  fi

  echo "BIOS settings updated for ${ILO_IP}."

  # 3. Reboot the server (force restart)
  REBOOT_RESULT=$(curl -s -k -X POST -H "Content-Type: application/json" \
    -H "X-Auth-Token: ${SESSION_KEY}" \
    -d "{\"ResetType\":\"ForceRestart\"}" \
    https://${ILO_IP}/redfish/v1/systems/1/Actions/ComputerSystem.Reset)

  if [[ "$REBOOT_RESULT" == *"error"* ]]; then
    echo "ERROR: Failed to reboot server ${ILO_IP}. Response: $REBOOT_RESULT"
    return 1
  fi

  echo "Server reboot initiated for ${ILO_IP}."

  # 4. Logout
  curl -s -k -X DELETE -H "X-Auth-Token: ${SESSION_KEY}" https://${ILO_IP}/redfish/v1/SessionService/Sessions

  echo "Session closed for ${ILO_IP}."
}

# Read iLO IPs from file
if [ ! -f ilo_ips.txt ]; then
  echo "ERROR: File 'ilo_ips.txt' not found!"
  exit 1
fi

while read -r ILO_IP; do
  [[ -z "$ILO_IP" || "${ILO_IP:0:1}" == "#" ]] && continue # Skip empty lines or comments
  set_bios_settings "${ILO_IP}"
done < ilo_ips.txt

echo "Done."