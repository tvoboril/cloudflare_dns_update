#!/bin/bash
# initial data; they need to be filled by the user
## API token; e.g. FErsdfklw3er59dUlDce44-3D43dsfs3sddsFoD3
api_token=<YOUR_API_TOKEN>
## the email address associated with the Cloudflare account; e.g. email@gmail.com
email=<YOUR_EMAIL>
## the zone (domain) should be modified; e.g. example.com
zone_name=<YOUR_DOMAIN>
## the dns record (sub-domain) should be modified; e.g. sub.example.com
dns_record=<YOUR_SUB_DOMAIN>
## the override token to allow updates to existing records true=allow, false=disallow
dns_override=false
## request origin certificate (for communication with Cloudflare only)
dns_origin_certificate=$1
service_key=<YOU_SERVICE_KEY>

# get the basic data
ipv4=$(curl -s -X GET -4 https://ifconfig.co)
user_id=$(curl -s -X GET "https://api.cloudflare.com/client/v4/user/tokens/verify" \
               -H "Authorization: Bearer $api_token" \
               -H "Content-Type:application/json" \
          | jq -r '{"result"}[] | .id'
         )
# Get IPv4
if [ $ipv4 ]; then echo -e "\033[0;32m [+] Your public IPv4 address: $ipv4"; else echo -e "\033[0;33m [!] Unable to get any public IPv4 address."; fi

# Validate user API and the email
if [ $user_id ]; then
    zone_id=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones?name=$zone_name&status=active" \
                   -H "Content-Type: application/json" \
                   -H "X-Auth-Email: $email" \
                   -H "Authorization: Bearer $api_token" \
              | jq -r '{"result"}[] | .[0] | .id'
             )
    # check if the zone ID is avilable
    if [ $zone_id ]; then
        # check if there is any IP version 4
        if [ $ipv4 ]; then
            dns_record_a_id=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/$zone_id/dns_records?type=A&name=$dns_record"  \
                                   -H "Content-Type: application/json" \
                                   -H "X-Auth-Email: $email" \
                                   -H "Authorization: Bearer $api_token"
                             )
            # if the IPv4 exist
            dns_record_a_ip=$(echo $dns_record_a_id |  jq -r '{"result"}[] | .[0] | .content')
            if [ $dns_record_a_ip != $ipv4 ]; then
                if [ $dns_record_a_ip = null ]; then
                    # create the A record
                    curl -s -X POST "https://api.cloudflare.com/client/v4/zones/$zone_id/dns_records" \
                        -H "X-Auth-Email: $email" \
                        -H "Authorization: Bearer $api_token" \
                        -H "Content-Type: application/json" \
                        --data "{\"type\":\"A\",\"name\":\"$dns_record\",\"content\":\"$ipv4\",\"ttl\":1,\"proxied\":false}" \
                    | jq -r '.errors'
                    # write the result
                    echo -e "\033[0;32m [+] The A record $dns_record was CREATED on Cloudflare with an address of: $ipv4"
                else
                    if [ $dns_override = true ]; then
                        # change the A record
                        curl -s -X PUT "https://api.cloudflare.com/client/v4/zones/$zone_id/dns_records/$(echo $dns_record_a_id | jq -r '{"result"}[] | .[0] | .id')" \
                             -H "Content-Type: application/json" \
                             -H "X-Auth-Email: $email" \
                             -H "Authorization: Bearer $api_token" \
                             --data "{\"type\":\"A\",\"name\":\"$dns_record\",\"content\":\"$ipv4\",\"ttl\":1,\"proxied\":false}" \
                        | jq -r '.errors'
                        # write the result
                        echo -e "\033[0;32m [+] The A record $dns_record was UPDATED on Cloudflare from: $dns_record_a_ip to an address of: $ipv4"
                    else
                        echo -e "\033[0;31m [-] Updates to $dns_record are not allowed, pass the correct token to override."
                    fi
                fi
            else
                echo -e "\033[0;37m [~] The current IPv4 address and the A record for $dns_record on Cloudflare are the same; there is no need to apply it."
            fi
        fi
    else
        echo -e "\033[0;31m [-] There is a problem with getting the Zone ID (subdomain) or the email address (username). Check them and try again."
    fi
else
    echo -e "\033[0;31m [-] There is a problem with either the API token. Check it and try again."
fi

# if user has passed "withcert" to command, request origin cert
if [ $dns_origin_certificate = withcert ]; then
    # create Certificate Request
    openssl req -nodes -newkey rsa:2048 -keyout private.key -out request.csr -subj "/CN=$dns_record"
    # convert csr to newline-encoded format
    dns_csr=$(awk 'NF {sub(/\r/, ""); printf "%s\\n",$0;}' request.csr)
    # request certififate from Cloudflare and output as cert
    curl -s -X POST "https://api.cloudflare.com/client/v4/certificates" \
          -H "X-Auth-User-Service-Key: $service_key" \
          -H "Content-Type: application/json" \
           --data "{\"hostname\":\"$dns_record\",\"requested_validity\":5475,\"request_type\":\"origin-rsa\",\"csr\":\"$dns_csr\"}" \
    | jq -r '.result.certificate' > public.cert
 fi
