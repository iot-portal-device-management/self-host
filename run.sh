#!/usr/bin/env bash

# Define a variable for the Docker registry mirror URL
docker_registry_mirror_url="https://dockerhubcache.caas.intel.com"

PS3='Select the closest proxy server to this system: '
proxys=("United States" "India" "Israel" "Ireland" "Germany" "Malaysia" "China" "DMZ")
proxy_servers=("proxy-us.intel.com" "proxy-iind.intel.com" "proxy-iil.intel.com" "proxy-ir.intel.com" "proxy-mu.intel.com" "proxy-png.intel.com" "proxy-prc.intel.com" "proxy-dmz.intel.com")

select proxy in "${proxys[@]}"
do
  case $proxy in
    "United States") server=${proxy_servers[0]} ;;
    "India") server=${proxy_servers[1]} ;;
    "Israel") server=${proxy_servers[2]} ;;
    "Ireland") server=${proxy_servers[3]} ;;
    "Germany") server=${proxy_servers[4]} ;;
    "Malaysia") server=${proxy_servers[5]} ;;
    "China") server=${proxy_servers[6]} ;;
    "DMZ") server=${proxy_servers[7]} ;;
    *) echo "Invalid proxy"; continue ;;
  esac
  break
done

# Define variables for proxy ports
http_https_port=912
ftp_port=21
socks_port=1080

# Define a variable for the autoproxy URL
autoproxy_url="http://wpad.intel.com/wpad.dat"

# Define a single variable for the proxy exclusion list
proxy_exclusion_list="backend,trainer-runner,task-runner,postgres,redis,chromadb,host.docker.internal,*.fm.intel.com,fm.intel.com,*.goto.intel.com,goto.intel.com,*.certificates.intel.com,certificates.intel.com,*.iglb.intel.com,iglb.intel.com,*.gfx-assets.intel.com,gfx-assets.intel.com,*.caas.intel.com,caas.intel.com,*.devtools.intel.com,devtools.intel.com,ubit-artifactory-or.intel.com,ubit-artifactory-sh.intel.com,10.0.0.0/8,192.168.0.0/16,localhost,.local,127.0.0.0/8,134.134.0.0/16"

# Append the system's IP address to the proxy exclusion list
system_ip=$(ip route get 1 | awk '{print $7}' | head -1)
proxy_exclusion_list="${proxy_exclusion_list},${system_ip}"

# Check if the script is run as root
if [ "$(id -u)" -eq 0 ]; then
  SUDO=""
else
  SUDO="sudo"
fi

function add_line() {
  local file=$1
  local newline=$2
  local searchstring=$3
  local linenum

  if [ -e "$file" ]; then
    linenum=$(grep -n "$searchstring" "$file" | grep -Eo '^[^:]+')
    if [ $? -eq 0 ]; then
      local safenewline
      safenewline=$(printf "%s" "$newline" | sed -e 's/[\/&]/\\&/g')
      $SUDO sed -i "${linenum}s/.*/${safenewline}/" "$file"
    else
      $SUDO bash -c "echo '$newline' >> $file"
    fi
  else
    $SUDO bash -c "echo '$newline' >> $file"
  fi
}

function setup_proxies() {
  add_line "/etc/environment" "http_proxy=http://${server}:${http_https_port}" "http_proxy"
  add_line "/etc/environment" "https_proxy=http://${server}:${http_https_port}" "https_proxy"
  add_line "/etc/environment" "ftp_proxy=http://${server}:${ftp_port}" "ftp_proxy"
  add_line "/etc/environment" "socks_proxy=http://${server}:${socks_port}" "socks_proxy"
  add_line "/etc/environment" "no_proxy=${proxy_exclusion_list}" "no_proxy"
  add_line "/etc/environment" "HTTP_PROXY=http://${server}:${http_https_port}" "HTTP_PROXY"
  add_line "/etc/environment" "HTTPS_PROXY=http://${server}:${http_https_port}" "HTTPS_PROXY"
  add_line "/etc/environment" "FTP_PROXY=http://${server}:${ftp_port}" "FTP_PROXY"
  add_line "/etc/environment" "SOCKS_PROXY=http://${server}:${socks_port}" "SOCKS_PROXY"
  add_line "/etc/environment" "NO_PROXY=${proxy_exclusion_list}" "NO_PROXY"
}

function setup_time() {
  $SUDO timedatectl set-timezone Asia/Kuala_Lumpur
  $SUDO timedatectl set-local-rtc false
  $SUDO timedatectl set-ntp false
  $SUDO date -s "$(https_proxy=http://${server}:${http_https_port} wget --no-check-certificate --server-response --spider https://google.com 2>&1 | grep -i '^ *Date:' | head -1 | sed 's/^[^:]*: //')"
  # Install hwclock
  $SUDO apt update -y
  $SUDO apt install util-linux-extra -y  || true
  $SUDO hwclock --systohc
}

function setup_autoproxy() {
  if command -v gsettings >/dev/null 2>&1; then
    gsettings set org.gnome.system.proxy mode 'auto'
    gsettings set org.gnome.system.proxy autoconfig-url "$autoproxy_url"
    gsettings set org.gnome.system.proxy ignore-hosts "['${proxy_exclusion_list//,/','}']"
    $SUDO gsettings set org.gnome.system.proxy mode 'auto'
    $SUDO gsettings set org.gnome.system.proxy autoconfig-url "$autoproxy_url"
    $SUDO gsettings set org.gnome.system.proxy ignore-hosts "['${proxy_exclusion_list//,/','}']"
  fi
}

function setup_ssh() {
  echo 'Do you want to setup SSH as well? (Y/N)'
  read -r varssh
  case $varssh in
    [Yy]*) 
      $SUDO apt update
      echo yes Y | $SUDO apt install openssh-server 
      ;;
    *) echo "Thank You" ;;
  esac
}

function setup_docker_proxy() {
  echo 'Do you want to configure Docker proxy settings as well? (Y/N)'
  read -r vardocker
  case $vardocker in
    [Yy]*)
      mkdir -p ~/.docker
      cat <<EOF > ~/.docker/config.json
{
  "proxies": {
    "default": {
      "httpProxy": "http://${server}:${http_https_port}",
      "httpsProxy": "http://${server}:${http_https_port}",
      "noProxy": "${proxy_exclusion_list}"
    }
  }
}
EOF
      echo "Docker proxy settings configured."

      # Configure Docker daemon proxy settings
      $SUDO mkdir -p /etc/systemd/system/docker.service.d
      $SUDO bash -c "cat <<EOF > /etc/systemd/system/docker.service.d/http-proxy.conf
[Service]
Environment=\"HTTP_PROXY=http://${server}:${http_https_port}\"
Environment=\"HTTPS_PROXY=http://${server}:${http_https_port}\"
Environment=\"NO_PROXY=${proxy_exclusion_list}\"
EOF"
      $SUDO systemctl daemon-reload
      $SUDO systemctl restart docker
      echo "Docker daemon proxy settings configured."
      ;;
    *) echo "Docker proxy configuration skipped." ;;
  esac
}

function setup_docker_registry_mirror() {
  echo 'Do you want to configure Docker registry mirrors as well? (Y/N)'
  read -r varmirror
  case $varmirror in
    [Yy]*)
      $SUDO mkdir -p /etc/docker
      $SUDO bash -c "cat <<EOF > /etc/docker/daemon.json
{
  \"registry-mirrors\": [\"$docker_registry_mirror_url\"]
}
EOF"
      $SUDO systemctl restart docker
      echo "Docker registry mirrors configured."
      ;;
    *) echo "Docker registry mirror configuration skipped." ;;
  esac
}

function install_trust_chains() {
  echo 'Do you want to install trust chains as well? (Y/N)'
  read -r vartrust
  case $vartrust in
    [Yy]*)
      set -e
      source /etc/os-release

      # Install unzip and wget if not installed
      if ! [ -x "$(command -v unzip)" ]; then
        echo 'Installing unzip...'
        $SUDO apt-get update && $SUDO apt-get install -y unzip
      fi

      if ! [ -x "$(command -v wget)" ]; then
        echo 'Installing wget...'
        $SUDO apt-get update && $SUDO apt-get install -y wget
      fi

      case $NAME in
      Ubuntu)
          certs_folder='/usr/local/share/ca-certificates'
          cmd='/usr/sbin/update-ca-certificates'
          ;;
      SLES)
          certs_folder='/etc/pki/trust/anchors'
          cmd='/usr/sbin/update-ca-certificates'
          ;;
      Fedora)
          certs_folder='/etc/pki/ca-trust/source/anchors'
          cmd='/bin/update-ca-trust'
          ;;
      "CentOS Stream")
          certs_folder='/etc/pki/ca-trust/source/anchors'
          cmd='/bin/update-ca-trust extract'
          ;;
      "Red Hat Enterprise Linux")
          certs_folder='/etc/pki/ca-trust/source/anchors'
          cmd='/bin/update-ca-trust'
          ;;
      *)
          echo "Error: unsupported OS $NAME"
          exit 1
          ;;
      esac

      temp_folder=$(mktemp -d)
      for certs_file in "IntelSHA256TrustChain-Base64.zip" "IntelSHA384TrustChain-Base64.zip" "IntelSHA512TrustChain-Base64.zip"; do
        certs_url="http://certificates.intel.com/repository/certificates/TrustBundles/$certs_file"
        $SUDO wget --no-proxy $certs_url -O $temp_folder/$certs_file
        $SUDO unzip -u $temp_folder/$certs_file -d $certs_folder
        $SUDO rm $temp_folder/$certs_file
      done
      rmdir $temp_folder
      
      $SUDO chmod 644 $certs_folder/*.crt
      $SUDO $cmd

      # Restart Docker service
      $SUDO systemctl restart docker
      ;;
    *) echo "Trust chains installation skipped." ;;
  esac
}

setup_proxies
setup_time
setup_autoproxy
setup_ssh
setup_docker_proxy
setup_docker_registry_mirror
install_trust_chains

echo 'Please restart your system for changes to take effect.'
