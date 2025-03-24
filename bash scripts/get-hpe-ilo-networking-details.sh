#!/bin/bash

# Script to retrieve network card information from HPE iLO via Redfish API
#
#   run with ./get-hpe-ilo-networking-details.sh -i
# 
#   Author        Yannick Gerber, yannick.gerber@soultec.ch
#   Change Log    V1.00, 22/02/2025 - Initial version


# Configuration variables
ILO_HOST=""
ILO_USERNAME="Administrator"
ILO_PASSWORD=""

# Display usage information
usage() {
  echo "Usage: $0 -h <iLO_host> -u <username> -p <password>"
  echo
  echo "Options:"
  echo "  -h    iLO hostname or IP address"
  echo "  -u    iLO username"
  echo "  -p    iLO password"
  echo "  -i    Ignore SSL certificate verification (optional)"
  echo "  -v    Verbose output (optional)"
  echo "  -d    Debug mode - show raw responses (optional)"
  echo "  -e    Show extra details (optional)"
  echo "  -?    Display this help message"
  exit 1
}

# Parse command line options
IGNORE_SSL=0
VERBOSE=0
DEBUG=0
EXTRA_DETAILS=0

while getopts "h:u:p:ivde?" opt; do
  case $opt in
    h) ILO_HOST="$OPTARG" ;;
    u) ILO_USERNAME="$OPTARG" ;;
    p) ILO_PASSWORD="$OPTARG" ;;
    i) IGNORE_SSL=1 ;;
    v) VERBOSE=1 ;;
    d) DEBUG=1 ;;
    e) EXTRA_DETAILS=1 ;;
    \?|*) usage ;;
  esac
done

# Check if required parameters are provided
if [ -z "$ILO_HOST" ] || [ -z "$ILO_USERNAME" ] || [ -z "$ILO_PASSWORD" ]; then
  echo "Error: Missing required parameters"
  usage
fi

# Set up curl options for SSL verification
CURL_OPTS=""
if [ $IGNORE_SSL -eq 1 ]; then
  CURL_OPTS="-k"
fi

# Function to execute curl command with proper error handling
do_curl() {
  local url="$1"
  local result
  
  if [ $VERBOSE -eq 1 ]; then
    echo "Requesting: $url"
  fi
  
  result=$(curl -s $CURL_OPTS -u "$ILO_USERNAME:$ILO_PASSWORD" "$url")
  curl_status=$?
  
  if [ $curl_status -ne 0 ]; then
    echo "Error: Failed to connect to iLO at $ILO_HOST (curl status: $curl_status)"
    exit 1
  fi
  
  # Check if response is empty
  if [ -z "$result" ]; then
    echo "Error: Empty response from server"
    exit 1
  fi
  
  # Debug mode - show raw response
  if [ $DEBUG -eq 1 ]; then
    echo "Raw response from $url:"
    echo "$result"
    echo "---------------------------------------------"
  fi
  
  # Check if response is valid JSON
  if ! echo "$result" | jq . >/dev/null 2>&1; then
    echo "Error: Invalid JSON response from the server:"
    echo "$result" | head -n 20
    exit 1
  fi
  
  # Check for error in response
  if echo "$result" | jq -e 'has("error")' >/dev/null 2>&1 && [ "$(echo "$result" | jq -r 'has("error")')" = "true" ]; then
    echo "API Error:"
    echo "$result" | jq .
    exit 1
  fi
  
  echo "$result"
}

# Function to follow OData links and collect all instances of a certain resource type
# Usage: find_resources <start_url> <resource_type>
find_resources() {
  local start_url="$1"
  local resource_type="$2"
  local max_depth="${3:-3}"  # Default max depth is 3
  local current_depth="${4:-0}"  # Current depth starts at 0
  local visited_urls="${5:-}"  # Keep track of visited URLs
  local found_resources=""
  
  # Check if we've reached maximum depth
  if [ "$current_depth" -ge "$max_depth" ]; then
    return 0
  fi
  
  # Check if we've already visited this URL
  if [[ "$visited_urls" == *"$start_url"* ]]; then
    return 0
  fi
  
  # Add to visited URLs
  visited_urls="$visited_urls $start_url"
  
  if [ $VERBOSE -eq 1 ]; then
    echo "Exploring: $start_url (depth $current_depth)"
  fi
  
  # Get resource
  local resource=$(do_curl "$start_url")
  
  # Check if this is the resource type we're looking for
  local odata_type=$(echo "$resource" | jq -r '."@odata.type" // ""')
  if [[ "$odata_type" == *"$resource_type"* ]]; then
    if [ $VERBOSE -eq 1 ]; then
      echo "Found $resource_type resource at $start_url"
    fi
    echo "$start_url"
  fi
  
  # Check for collection members
  if echo "$resource" | jq -e '.Members' >/dev/null 2>&1; then
    local member_urls=$(echo "$resource" | jq -r '.Members[]."@odata.id" // []')
    for url in $member_urls; do
      local next_url="https://$ILO_HOST$url"
      local resources=$(find_resources "$next_url" "$resource_type" "$max_depth" "$((current_depth + 1))" "$visited_urls")
      if [ -n "$resources" ]; then
        found_resources="$found_resources $resources"
      fi
    done
  fi
  
  # Look for other potentially interesting links
  local interesting_properties="Links NetworkAdapters NetworkInterfaces EthernetInterfaces"
  for prop in $interesting_properties; do
    if echo "$resource" | jq -e ".$prop" >/dev/null 2>&1; then
      # Check if it has @odata.id directly
      if echo "$resource" | jq -e ".$prop[\"@odata.id\"]" >/dev/null 2>&1; then
        local next_url="https://$ILO_HOST$(echo "$resource" | jq -r ".$prop[\"@odata.id\"]")"
        local resources=$(find_resources "$next_url" "$resource_type" "$max_depth" "$((current_depth + 1))" "$visited_urls")
        if [ -n "$resources" ]; then
          found_resources="$found_resources $resources"
        fi
      # Check if it has members with odata.id
      elif echo "$resource" | jq -e ".$prop[] | has(\"@odata.id\")" >/dev/null 2>&1; then
        local member_urls=$(echo "$resource" | jq -r ".$prop[]?[\"@odata.id\"]")
        for url in $member_urls; do
          local next_url="https://$ILO_HOST$url"
          local resources=$(find_resources "$next_url" "$resource_type" "$max_depth" "$((current_depth + 1))" "$visited_urls")
          if [ -n "$resources" ]; then
            found_resources="$found_resources $resources"
          fi
        done
      fi
    fi
  done
  
  echo "$found_resources"
}

# Function to print network interface information
print_network_interface() {
  local url="$1"
  local interface=$(do_curl "$url")
  
  local name=$(echo "$interface" | jq -r '.Name // .Id // "Unknown"')
  local id=$(echo "$interface" | jq -r '.Id // "Unknown ID"')
  local mac=$(echo "$interface" | jq -r '.MACAddress // .MacAddress // "Unknown MAC"')
  local status=$(echo "$interface" | jq -r '.Status.State // "Unknown Status"')
  local speed=$(echo "$interface" | jq -r '.SpeedMbps // .LinkSpeedMbps // "Unknown"')
  
  echo "Interface: $name (ID: $id)"
  if [ "$mac" != "Unknown MAC" ] && [ "$mac" != "null" ]; then
    echo "MAC Address: $mac"
  fi
  echo "Status: $status"
  
  if [ "$speed" != "Unknown" ] && [ "$speed" != "null" ]; then
    echo "Speed: ${speed} Mbps"
  fi
  
  # If extra details requested, show more information
  if [ $EXTRA_DETAILS -eq 1 ]; then
    # Get more details if available
    local fqdn=$(echo "$interface" | jq -r '.FQDN // .HostName // "N/A"')
    if [ "$fqdn" != "N/A" ] && [ "$fqdn" != "null" ]; then
      echo "FQDN: $fqdn"
    fi
    
    # Check for IPv4 addresses
    if echo "$interface" | jq -e '.IPv4Addresses // .IPv4Address' >/dev/null 2>&1; then
      echo "IPv4 Addresses:"
      echo "$interface" | jq -r '.IPv4Addresses[]? // .IPv4Address[]? | "  Address: " + (.Address // .IPAddress // "N/A") + ", Subnet: " + (.SubnetMask // "N/A") + ", Gateway: " + (.Gateway // .GatewayIPAddress // "N/A")'
    fi
    
    # Check for additional properties
    local additional_props="InterfaceEnabled FullDuplex AutoNeg LinkStatus"
    for prop in $additional_props; do
      if echo "$interface" | jq -e ".$prop" >/dev/null 2>&1; then
        local value=$(echo "$interface" | jq -r ".$prop")
        if [ "$value" != "null" ]; then
          echo "$prop: $value"
        fi
      fi
    done
  fi
  
  echo "----------------------------------------"
}

# Function to search for ports or child objects of a network interface
check_for_network_ports() {
  local url="$1"
  local interface=$(do_curl "$url")
  
  # Check for NetworkPorts link
  if echo "$interface" | jq -e '.NetworkPorts' >/dev/null 2>&1; then
    local ports_url=$(echo "$interface" | jq -r '.NetworkPorts["@odata.id"]')
    local ports_collection=$(do_curl "https://$ILO_HOST$ports_url")
    
    if echo "$ports_collection" | jq -e '.Members' >/dev/null 2>&1; then
      local port_urls=$(echo "$ports_collection" | jq -r '.Members[]."@odata.id"')
      
      for port_url in $port_urls; do
        local port=$(do_curl "https://$ILO_HOST$port_url")
        
        local port_id=$(echo "$port" | jq -r '.Id // "Unknown Port"')
        local mac=$(echo "$port" | jq -r '.MACAddress // .MacAddress // "Unknown MAC"')
        local status=$(echo "$port" | jq -r '.Status.State // "Unknown Status"')
        
        echo "  Port: $port_id"
        if [ "$mac" != "Unknown MAC" ] && [ "$mac" != "null" ]; then
          echo "  MAC Address: $mac"
        fi
        echo "  Status: $status"
        
        # If extra details requested, show more information
        if [ $EXTRA_DETAILS -eq 1 ]; then
          local speed=$(echo "$port" | jq -r '.SpeedMbps // .LinkSpeedMbps // "Unknown"')
          if [ "$speed" != "Unknown" ] && [ "$speed" != "null" ]; then
            echo "  Speed: ${speed} Mbps"
          fi
          
          local additional_props="LinkStatus ActiveLinkTechnology SupportedLinkCapabilities"
          for prop in $additional_props; do
            if echo "$port" | jq -e ".$prop" >/dev/null 2>&1; then
              local value=$(echo "$port" | jq -r ".$prop")
              if [ "$value" != "null" ]; then
                echo "  $prop: $value"
              fi
            fi
          done
        fi
        
        echo "  -------------------------------------------"
      done
    fi
  fi
}

# Check if jq is installed
if ! command -v jq &>/dev/null; then
  echo "Error: This script requires 'jq' to be installed."
  echo "Please install it using your package manager."
  echo "For example: apt-get install jq (Debian/Ubuntu) or yum install jq (RHEL/CentOS)"
  exit 1
fi

# Start exploration from root Redfish endpoint
base_url="https://$ILO_HOST/redfish/v1"
echo "Exploring Redfish API to discover network interfaces..."

# Get root document
root_resource=$(do_curl "$base_url")

# First try direct paths that are commonly used
found_interfaces=0

# Try common direct paths
echo "Checking common paths for network interfaces..."

# 1. Check Manager EthernetInterfaces path
if echo "$root_resource" | jq -e '.Managers' >/dev/null 2>&1; then
  managers_url=$(echo "$root_resource" | jq -r '.Managers["@odata.id"]')
  managers=$(do_curl "https://$ILO_HOST$managers_url")
  
  if echo "$managers" | jq -e '.Members[0]' >/dev/null 2>&1; then
    manager_url=$(echo "$managers" | jq -r '.Members[0]["@odata.id"]')
    manager=$(do_curl "https://$ILO_HOST$manager_url")
    
    if echo "$manager" | jq -e '.EthernetInterfaces' >/dev/null 2>&1; then
      ethernet_url=$(echo "$manager" | jq -r '.EthernetInterfaces["@odata.id"]')
      interfaces=$(do_curl "https://$ILO_HOST$ethernet_url")
      
      if echo "$interfaces" | jq -e '.Members' >/dev/null 2>&1 && [ "$(echo "$interfaces" | jq '.Members | length')" -gt 0 ]; then
        echo "Found network interfaces via Manager.EthernetInterfaces path:"
        echo "======================================================="
        
        interface_urls=$(echo "$interfaces" | jq -r '.Members[]."@odata.id"')
        for url in $interface_urls; do
          print_network_interface "https://$ILO_HOST$url"
          found_interfaces=$((found_interfaces + 1))
        done
      fi
    fi
  fi
fi

# 2. Check Systems path for NetworkInterfaces
if echo "$root_resource" | jq -e '.Systems' >/dev/null 2>&1; then
  systems_url=$(echo "$root_resource" | jq -r '.Systems["@odata.id"]')
  systems=$(do_curl "https://$ILO_HOST$systems_url")
  
  if echo "$systems" | jq -e '.Members[0]' >/dev/null 2>&1; then
    system_url=$(echo "$systems" | jq -r '.Members[0]["@odata.id"]')
    system=$(do_curl "https://$ILO_HOST$system_url")
    
    # Check for NetworkInterfaces in the system
    if echo "$system" | jq -e '.NetworkInterfaces' >/dev/null 2>&1; then
      network_url=$(echo "$system" | jq -r '.NetworkInterfaces["@odata.id"]')
      networks=$(do_curl "https://$ILO_HOST$network_url")
      
      if echo "$networks" | jq -e '.Members' >/dev/null 2>&1 && [ "$(echo "$networks" | jq '.Members | length')" -gt 0 ]; then
        echo "Found network interfaces via Systems.NetworkInterfaces path:"
        echo "======================================================="
        
        network_urls=$(echo "$networks" | jq -r '.Members[]."@odata.id"')
        for url in $network_urls; do
          full_url="https://$ILO_HOST$url"
          interface=$(do_curl "$full_url")
          
          name=$(echo "$interface" | jq -r '.Name // .Id // "Unknown"')
          id=$(echo "$interface" | jq -r '.Id // "Unknown ID"')
          
          echo "Network Interface: $name (ID: $id)"
          check_for_network_ports "$full_url"
          found_interfaces=$((found_interfaces + 1))
        done
      fi
    fi
    
    # Check for EthernetInterfaces directly in the system
    if echo "$system" | jq -e '.EthernetInterfaces' >/dev/null 2>&1; then
      ethernet_url=$(echo "$system" | jq -r '.EthernetInterfaces["@odata.id"]')
      interfaces=$(do_curl "https://$ILO_HOST$ethernet_url")
      
      if echo "$interfaces" | jq -e '.Members' >/dev/null 2>&1 && [ "$(echo "$interfaces" | jq '.Members | length')" -gt 0 ]; then
        echo "Found network interfaces via Systems.EthernetInterfaces path:"
        echo "======================================================="
        
        interface_urls=$(echo "$interfaces" | jq -r '.Members[]."@odata.id"')
        for url in $interface_urls; do
          print_network_interface "https://$ILO_HOST$url"
          found_interfaces=$((found_interfaces + 1))
        done
      fi
    fi
  fi
fi

# 3. Check Chassis path for NetworkAdapters
if echo "$root_resource" | jq -e '.Chassis' >/dev/null 2>&1; then
  chassis_url=$(echo "$root_resource" | jq -r '.Chassis["@odata.id"]')
  chassis_collection=$(do_curl "https://$ILO_HOST$chassis_url")
  
  if echo "$chassis_collection" | jq -e '.Members' >/dev/null 2>&1; then
    chassis_urls=$(echo "$chassis_collection" | jq -r '.Members[]."@odata.id"')
    
    for ch_url in $chassis_urls; do
      chassis=$(do_curl "https://$ILO_HOST$ch_url")
      
      if echo "$chassis" | jq -e '.NetworkAdapters' >/dev/null 2>&1; then
        adapters_url=$(echo "$chassis" | jq -r '.NetworkAdapters["@odata.id"]')
        adapters=$(do_curl "https://$ILO_HOST$adapters_url")
        
        if echo "$adapters" | jq -e '.Members' >/dev/null 2>&1 && [ "$(echo "$adapters" | jq '.Members | length')" -gt 0 ]; then
          echo "Found network adapters via Chassis.NetworkAdapters path:"
          echo "======================================================="
          
          adapter_urls=$(echo "$adapters" | jq -r '.Members[]."@odata.id"')
          for url in $adapter_urls; do
            full_url="https://$ILO_HOST$url"
            adapter=$(do_curl "$full_url")
            
            name=$(echo "$adapter" | jq -r '.Name // .Id // "Unknown"')
            id=$(echo "$adapter" | jq -r '.Id // "Unknown ID"')
            
            echo "Network Adapter: $name (ID: $id)"
            
            # Check for manufacturer/model info
            manufacturer=$(echo "$adapter" | jq -r '.Manufacturer // "Unknown Manufacturer"')
            model=$(echo "$adapter" | jq -r '.Model // "Unknown Model"')
            
            if [ "$manufacturer" != "Unknown Manufacturer" ] && [ "$manufacturer" != "null" ]; then
              echo "Manufacturer: $manufacturer"
            fi
            
            if [ "$model" != "Unknown Model" ] && [ "$model" != "null" ]; then
              echo "Model: $model"
            fi
            
            # Check for NetworkPorts
            if echo "$adapter" | jq -e '.NetworkPorts' >/dev/null 2>&1; then
              ports_url=$(echo "$adapter" | jq -r '.NetworkPorts["@odata.id"]')
              ports=$(do_curl "https://$ILO_HOST$ports_url")
              
              if echo "$ports" | jq -e '.Members' >/dev/null 2>&1 && [ "$(echo "$ports" | jq '.Members | length')" -gt 0 ]; then
                port_urls=$(echo "$ports" | jq -r '.Members[]."@odata.id"')
                
                for port_url in $port_urls; do
                  port=$(do_curl "https://$ILO_HOST$port_url")
                  
                  port_id=$(echo "$port" | jq -r '.Id // "Unknown Port"')
                  port_name=$(echo "$port" | jq -r '.Name // "Unknown Name"')
                  mac=$(echo "$port" | jq -r '.MACAddress // .MacAddress // "Unknown MAC"')
                  
                  echo "  Port: $port_name (ID: $port_id)"
                  if [ "$mac" != "Unknown MAC" ] && [ "$mac" != "null" ]; then
                    echo "  MAC Address: $mac"
                  fi
                  
                  if [ $EXTRA_DETAILS -eq 1 ]; then
                    link_status=$(echo "$port" | jq -r '.LinkStatus // "Unknown"')
                    if [ "$link_status" != "Unknown" ] && [ "$link_status" != "null" ]; then
                      echo "  Link Status: $link_status"
                    fi
                    
                    link_speed=$(echo "$port" | jq -r '.CurrentLinkSpeed // "Unknown"')
                    if [ "$link_speed" != "Unknown" ] && [ "$link_speed" != "null" ]; then
                      echo "  Current Link Speed: $link_speed"
                    fi
                  fi
                  
                  echo "  -------------------------------------------"
                done
              fi
            fi
            
            found_interfaces=$((found_interfaces + 1))
            echo "======================================================="
          done
        fi
      fi
    done
  fi
fi

# If no interfaces found through direct paths, try exploring
if [ $found_interfaces -eq 0 ]; then
  echo "No network interfaces found through common paths. Performing deeper API exploration..."
  
  # Look for EthernetInterface type
  ethernet_urls=$(find_resources "$base_url" "EthernetInterface" 4)
  
  if [ -n "$ethernet_urls" ]; then
    echo "Found EthernetInterface resources through exploration:"
    echo "======================================================="
    
    for url in $ethernet_urls; do
      print_network_interface "$url"
      found_interfaces=$((found_interfaces + 1))
    done
  fi
  
  # Look for NetworkInterface type
  network_urls=$(find_resources "$base_url" "NetworkInterface" 4)
  
  if [ -n "$network_urls" ]; then
    echo "Found NetworkInterface resources through exploration:"
    echo "======================================================="
    
    for url in $network_urls; do
      interface=$(do_curl "$url")
      
      name=$(echo "$interface" | jq -r '.Name // .Id // "Unknown"')
      id=$(echo "$interface" | jq -r '.Id // "Unknown ID"')
      
      echo "Network Interface: $name (ID: $id)"
      check_for_network_ports "$url"
      found_interfaces=$((found_interfaces + 1))
    done
  fi
  
  # Look for NetworkAdapter type
  adapter_urls=$(find_resources "$base_url" "NetworkAdapter" 4)
  
  if [ -n "$adapter_urls" ]; then
    echo "Found NetworkAdapter resources through exploration:"
    echo "======================================================="
    
    for url in $adapter_urls; do
      adapter=$(do_curl "$url")
      
      name=$(echo "$adapter" | jq -r '.Name // .Id // "Unknown"')
      id=$(echo "$adapter" | jq -r '.Id // "Unknown ID"')
      
      echo "Network Adapter: $name (ID: $id)"
      check_for_network_ports "$url"
      found_interfaces=$((found_interfaces + 1))
    done
  fi
fi

# Summary
if [ $found_interfaces -eq 0 ]; then
  echo "No network interfaces found in the Redfish API."
  echo "Try running with the -d flag to see the raw responses for troubleshooting."
else
  echo "Total network interfaces/adapters found: $found_interfaces"
fi