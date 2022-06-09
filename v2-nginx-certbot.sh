#!/usr/bin/env bash
set -e

BLUE="\e[1;34m"
GREEN="\e[1;32m"
RED="\e[1;31m"
DEFAULT="\e[0m"

function blueln(){
  echo -e "${BLUE}${1}${DEFAULT}"
}

function greenln(){
  echo -e "${GREEN}${1}${DEFAULT}"
}

function redln(){
  echo -e "${RED}${1}${DEFAULT}"
}

if [[ $(id -u) -ne 0 ]]; then
  redln "\nPlease run the script as root user -> \"sudo ${0}\"\n"
  exit
fi

blueln "\nInstalling Nginx..."
sudo apt update
sudo apt install --upgrade nginx -y
clear
greenln "\nSuccessfully installed Nginx!"

blueln "\nInstalling Certbot..."
sudo snap install core; sudo snap refresh core
sudo apt-get remove certbot
sudo snap install --classic certbot
if [[ ! -L /usr/bin/certbot ]]; then
  sudo ln -s /snap/bin/certbot /usr/bin/certbot
fi
sudo snap set certbot trust-plugin-with-root=ok
clear
greenln "\nSuccessfully installed Certbot!\n"

read -p "Enter domains (space seperated) for which to get Let's Encrypt Certificates: " DOMAINS
CERT_DOMAINS=""
read -p "Enter email ID to use with certbot: " EMAIL

for DOMAIN in $DOMAINS; do
  CERT_DOMAINS="${CERT_DOMAINS} -d ${DOMAIN}"
done

blueln "\nFetching certificates from Let's Encrypt..."
sudo certbot certonly --nginx -m ${EMAIL} --agree-tos ${CERT_DOMAINS}
clear
greenln "\nSuccessfully fetched all certificates!"

blueln "\nPerforming dry run..."
sudo certbot renew --dry-run
clear
greenln "\nDry run was successful!"

LE_DIR="${DOMAINS/ */}"
blueln "\nCreating nginx configuration files for all the domains...\n"
for DOMAIN in $DOMAINS; do
  if [[ -f "/etc/nginx/sites-available/${DOMAIN}" ]]; then
    read -n2 -p "Nginx config file for ${DOMAIN} exists already, do you want to replace it? (y/n): " ANS
    if [[ $ANS == "y" || $ANS == "Y" ]]; then
      blueln "Purging Nginx config file for ${DOMAIN}..."
      sudo rm /etc/nginx/sites-available/${DOMAIN} /etc/nginx/sites-enabled/${DOMAIN}
    fi
  fi

  if [[ ! -f "/etc/nginx/sites-available/${DOMAIN}" ]]; then
    read -p "Enter Port Number to proxy to for \"${DOMAIN}\": " PROXY_PASS_PORT
    read -p "Enter Path to proxy to for \"${DOMAIN}\": " PROXY_PASS_PATH
    [[ ${PROXY_PASS_PATH:0:1} == "/" ]] && PROXY_PASS_PATH=${PROXY_PASS_PATH:1}
      
    sudo cat > /etc/nginx/sites-available/${DOMAIN} << EOF

server {
   server_name ${DOMAIN};

   location / {
    proxy_pass http://localhost:${PROXY_PASS_PORT};
   }


  listen 443 ssl;
  ssl_certificate /etc/letsencrypt/live/${LE_DIR}/fullchain.pem;
  ssl_certificate_key /etc/letsencrypt/live/${LE_DIR}/privkey.pem;
  include /etc/letsencrypt/options-ssl-nginx.conf;
  ssl_dhparam /etc/letsencrypt/ssl-dhparams.pem;
}

server {
    if (\$host = ${DOMAIN}) {
        return 301 https://\$host\$request_uri;
    } 

   server_name ${DOMAIN};
    listen 80;
    return 404;
}
EOF
  sudo ln -s /etc/nginx/sites-available/${DOMAIN} /etc/nginx/sites-enabled/${DOMAIN}
  fi
  
  echo
done

if [[ -f "/etc/nginx/sites-available/default" ]]; then
  read -n2 -p "Do you want to delete the default nginx config file stored at \"/etc/nginx/sites-available/default\"? (y/n): " ANS
  if [[ $ANS == "y" || $ANS == "Y" ]]; then
    blueln "Purging Nginx default config file..."
    sudo rm /etc/nginx/sites-available/default /etc/nginx/sites-enabled/default
  fi
fi

clear
greenln "\nSuccessfully created all the nginx configuration files!"


blueln "\nReloading Nginx..."
sudo nginx -t
sudo systemctl reload nginx
clear
greenln "\nSuccessfully reloaded Nginx!"
greenln "Setup complete!\n"
