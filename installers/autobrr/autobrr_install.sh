#!/bin/bash

set -euo pipefail

# Warp copied from ultra.cc sonarr installation script originally by XAN and Raikiri

#Disclaimer

printf "\033[0;31mDisclaimer: This installer is unofficial and Ultra.cc staff will not support any issues with it\033[0m\n"
read -rp "Type confirm if you wish to continue: " input
if [ ! "$input" = "confirm" ]; then
  exit
fi

#Port-Picker by XAN & Raikiri

port=''
backup=''
status='fresh install'
while [ -z "${port}" ]; do
  app-ports show
  echo "Pick any application from the list above, that you're not currently using."
  echo "We'll be using this port for your autobrr application"
  read -rp "$(tput setaf 4)$(tput bold)Application name in full[Example: pyload]: $(tput sgr0)" appname
  proper_app_name=$(app-ports show | grep -i "${appname}" | head -n 1 | cut -c 7-) || proper_app_name=''
  port=$(app-ports show | grep -i "${appname}" | head -n 1 | awk '{print $1}') || port=''
  if [ -z "${port}" ]; then
    echo "$(tput setaf 1)Invalid choice! Please choose an application from the list and avoid typos.$(tput sgr0)"
    echo "$(tput bold)Listing all applications again..$(tput sgr0)"
    sleep 5
    clear
  fi
done
echo "$(tput setaf 2)Are you sure you want to use ${proper_app_name}'s port? type 'confirm' to proceed.$(tput sgr0)"
read -r input
if [ ! "${input}" = "confirm" ]; then
  exit
fi
echo

#Get password

while true; do
  read -rsp "The password you want to use for autobrr: " password
  echo
  read -rsp "Confirm the password: " password2
  echo
  [ "${password}" = "${password2}" ] && break
  echo "Passwords didn't match, try again."
done

#Perform Checks

if [ ! -d "${HOME}/tmp" ]; then
  mkdir -p "${HOME}/tmp"
fi

if [ ! -d "${HOME}/.apps/backup" ]; then
  mkdir -p "${HOME}/.apps/backup"
fi

if systemctl --user is-active --quiet "autobrr.service" || [ -f "${HOME}/.config/systemd/users/autobrr.service" ]; then
  systemctl --user stop "autobrr.service"
  systemctl --user --quiet disable "autobrr.service"
  echo
  echo "Disabled old autobrr instance."
fi

if [ -d "${HOME}/.apps/autobrr" ]; then
  echo
  echo "Old instance of autobrr detected. How do you wish to proceed? In the case of a fresh install the current AppData directory will be backed up."

  select status in 'Fresh Install' 'Update' quit; do

    case ${status} in
    'Fresh Install')
      status="fresh install"
      break
      ;;
    'Update')
      status='update'
      break
      ;;
    quit)
      exit 0
      ;;
    *)
      echo "Invalid option $REPLY"
      ;;
    esac
  done
fi

if [ -d "${HOME}/.apps/autobrr" ] && [ "${status}" == 'fresh install' ]; then
  backup="${HOME}/.apps/backup/autobrr-$(date +"%FT%H%M").bak.tar.gz"
  echo
  echo "Creating a backup of the current instance's AppData directory.."
  tar -czf "${backup}" -C "${HOME}/.apps/" "autobrr" && rm -rf "${HOME}/.apps/autobrr"
  echo
  echo "Installing fresh instance of autobrr.."
fi

#Get binaries

echo
echo "Pulling new binaries.."
parsedurl="https://github.com"$(curl -s https://github.com/autobrr/autobrr/releases/ | grep "/autobrr/autobrr/releases/download/v" | grep linux_x86_64 | head -1 | cut -d\" -f2)
echo $parsedurl
wget -qO "${HOME}"/tmp/autobrr.tar.gz --content-disposition $parsedurl
tar -xzf "${HOME}"/tmp/autobrr.tar.gz -C "${HOME}/bin"

#Install nginx conf

cat <<EOF | tee "${HOME}/.apps/nginx/proxy.d/autobrr.conf" >/dev/null
location /autobrr/ {
    proxy_pass              http://127.0.0.1:${port};
    proxy_http_version      1.1;
    proxy_set_header        X-Forwarded-Host       \$http_host;
    rewrite ^/autobrr/(.*) /\$1 break;
}
EOF

#Install Systemd service

cat <<EOF | tee "${HOME}"/.config/systemd/user/autobrr.service >/dev/null
[Unit]
Description=autobrr service
After=syslog.target network-online.target
[Service]
Type=simple
ExecStart=%h/bin/autobrr --config=%h/.apps/autobrr/
[Install]
WantedBy=multi-user.target
EOF

#Set port

if [ ! -d "${HOME}/.apps/autobrr" ]; then
  mkdir -p "${HOME}/.apps/autobrr"
fi

cat <<EOF | tee "${HOME}/.apps/autobrr/config.toml" >/dev/null
# config.toml

# Hostname / IP
#
# Default: "localhost"
#
host = "127.0.0.1"

# Port
#
# Default: 7474
#
port = ${port}

# Base url
# Set custom baseUrl eg /autobrr/ to serve in subdirectory.
# Not needed for subdomain, or by accessing with the :port directly.
#
# Optional
#
baseUrl = "/autobrr/"

# autobrr logs file
# If not defined, logs to stdout
#
# Optional
#
logPath = "${HOME}/.apps/autobrr/autobrr.log"

# Log level
#
# Default: "DEBUG"
#
# Options: "ERROR", "DEBUG", "INFO", "WARN"
#
#logLevel = "TRACE"

# Session secret
# Can be generated by running: head /dev/urandom | tr -dc A-Za-z0-9 | head -c16
sessionSecret = "$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c16)"
EOF

## Create user
if [ "${status}" == 'fresh install' ]; then
   echo $password | autobrrctl --config $HOME/.apps/autobrr create-user $USER
else
   echo $password | autobrrctl --config ~/.apps/autobrr change-password $USER
fi

#Start systemd service

echo "Starting autobrr.."
systemctl --user daemon-reload
systemctl --user --quiet enable --now "autobrr".service
sleep 10


if ! systemctl --user is-active --quiet "autobrr.service"; then
  echo "Your instance of autobrr failed to start properly, install aborted. Please check port selection, HDD IO and other resource utilization."
  exit 1
fi

app-nginx restart

#Relay information about backup

echo
if [ -n "${backup}" ]; then
  echo "AppData directory of the previous installation backed up at ${backup}"
  echo
fi

#Ensure that application is running

x=1
while [ ${x} -le 4 ]; do
  if systemctl --user is-active --quiet "autobrr.service"; then
    echo "${status^} complete."
    echo "You can access your autobrr instance of via the following URL:https://${USER}.${HOSTNAME}.usbx.me/autobrr"
    exit
  else
    if [ ${x} -ge 4 ]; then
      echo "autobrr failed to start. Try re-running the script and choose a different application's port."
      echo "It has to be an application that you do not plan to use at all."
      exit
    fi
    echo "autobrr failed to start."
    echo
    echo "Restarting autobrr ${x}/3 times.."
    echo
    systemctl --user restart "autobrr.service"
    sleep 10
    x=$(("${x}" + 1))
  fi
done
