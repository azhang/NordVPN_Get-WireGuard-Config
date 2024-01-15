#!/bin/bash

# Clear the output folder
#rm -f -r /output/*
#
#example: curl 'https://api.nordvpn.com/v1/servers/recommendations?filters\[country_id\]=2&\[servers_technologies\]\[identifier\]=wireguard_udp&limit=1"'    

api_url="https://api.nordvpn.com/v1/servers/recommendations?filters"
technology_filter="\[servers_technologies\]\[identifier\]=wireguard_udp"

# Get the country code from the country name (if provided) and add it to the API URL as a filter
echo $COUNTRY_CODE
if [[ -n ${COUNTRY_CODE} ]]; then
  country_id=$(curl --silent "https://api.nordvpn.com/v1/servers/countries" | jq --raw-output ".[] | select(.code == \"${COUNTRY_CODE}\") | [.name, .id] | \"\(.[1])\"")
  echo "[$(date -Iseconds)] Country ID: ${country_id}"
  country_filter="\[country_id\]=${country_id}"
  api_url="${api_url}${country_filter}&${technology_filter}"
  echo "[$(date -Iseconds)] API URL: ${api_url}"
else
  api_url="${api_url}${technology_filter}"
fi

# Get the chosen server
api_response=$(curl --retry 3 -LsS "${api_url}&${QUERY}&limit=1")
echo "${api_url}&${QUERY}&limit=1"
server_identifier=$(jq -r '.[]|.hostname' <<< "$api_response" | cut -d "." -f 1)
server_hostname=$(jq -r '.[]|.hostname' <<< "$api_response")
server_ip=$(jq -r '.[]|.station' <<< "$api_response")
server_city=$(jq -r '.[]|(.locations|.[]|.country|.city.name)' <<< "$api_response")
server_country=$(jq -r '.[]|(.locations|.[]|.country|.name)' <<< "$api_response")
server_public_key=$(jq -r '.[]|(.technologies|.[].metadata|.[].value)' <<< "$api_response")

echo "#################### Recommended Server ####################"
echo "Server Identifier: $server_identifier"
echo "Hostname: $server_hostname"
echo "IP: $server_ip"
echo "City: $server_city"
echo "Country: $server_country"
echo "Server Public Key: $server_public_key"
echo "############################################################"
echo ""

# Get client details
nordvpn login --token "${TOKEN}" || { echo 'exiting...' ; exit 1; }
nordvpn set technology NordLynx|| { nordvpn logout --persist-token; echo 'exiting...'; exit 1; }
nordvpn connect "$server_identifier" || { nordvpn logout --persist-token; echo 'exiting...'; exit 1; }

client_private_key=$(wg show nordlynx private-key)
client_ip_address=$(ip -o addr show dev nordlynx | awk '$3 == "inet" {print $4}')

echo "###################### Client Details ######################"
echo "Private Key: $client_private_key"
echo "IP Address: $client_ip_address"
echo "############################################################"
echo ""

# Construct config
config=$(cat << EOF
# Configuration for $server_hostname ($server_ip) - $server_city, $server_country
[Interface]
Address = $client_ip_address
PrivateKey = $client_private_key
DNS = ${DNS_SERVER:-9.9.9.9}

[Peer]
PublicKey = $server_public_key
AllowedIPs = 0.0.0.0/0
Endpoint = $server_hostname:51820
EOF
)

echo "##################### WireGuard Config #####################"
echo "$config"
echo "############################################################"

# Write config to the putput folder
echo "$config" > "/output/nordvpn-$server_identifier.conf"

# Close out
nordvpn disconnect
nordvpn logout --persist-token
exit 0
