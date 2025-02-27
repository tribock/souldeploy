#!/bin/bash

# Prompt for input variables
if [[ $# -eq 0 ]]
then
    read -p "Enter iLO IP address: " ilo_ip
else
    ilo_ip=$1
fi

if [[ $# -eq 1 ]]
then
    read -p "Enter iLO username: " ilo_user

else
    ilo_user=$2
fi

if [[ $# -eq 2 ]]
then
    read -s -p "Enter iLO password: " ilo_password

else
    ilo_password=$3
fi

echo

if [[ $# -eq 3 ]]
then
    read -p "Enter VLAN ID: " vlan_id

else
    vlan_id=$4
fi




# Function to make Redfish API calls
redfish_call() {
    local method="$1"
    local endpoint="$2"
    local data="$3"

    curl --insecure --silent --location \
        -u "${ilo_user}:${ilo_password}" \
        -H "Content-Type: application/json" \
        -X "$method" \
        "https://${ilo_ip}${endpoint}" \
        ${data:+-d "$data"}
}

# Set VLAN ID
echo "Setting VLAN ID..."
vlan_response=$(redfish_call "PATCH" "/redfish/v1/Systems/1/Bios/" \
    "{\"Attributes\": {\"VlanId\": \"${vlan_id}\", \"NetworkBootRetry\": \"Enabled\", \"PreBootNetworkEnv\": \"Auto\"}}")

if [[ $vlan_response == *"\"@odata.type\": \"#Bios.v1_0_0.Bios\""* ]]; then
    echo "VLAN ID set successfully."
else
    echo "Failed to set VLAN ID. Response:"
    echo "$vlan_response"
fi

# Set one-time boot to HTTP
echo "Setting one-time boot to HTTP..."
boot_response=$(redfish_call "PATCH" "/redfish/v1/Systems/1" \
    "{\"Boot\": {\"BootSourceOverrideTarget\": \"UefiHttp\", \"BootSourceOverrideEnabled\": \"Once\"}}")

if [[ $boot_response == *"\"BootSourceOverrideTarget\": \"UefiHttp\""* ]]; then
    echo "One-time boot to HTTP set successfully."
else
    echo "Failed to set one-time boot. Response:"
    echo "$boot_response"
fi

# Reboot the server
echo "Rebooting the server..."
reboot_response=$(redfish_call "POST" "/redfish/v1/Systems/1/Actions/ComputerSystem.Reset" \
    "{\"ResetType\": \"ForceRestart\"}")

if [[ $reboot_response == "{}" ]]; then
    echo "Server reboot initiated successfully."
else
    echo "Failed to initiate server reboot. Response:"
    echo "$reboot_response"
fi

echo "Script execution completed."
