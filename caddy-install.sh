#!/usr/bin/env bash
#
#
#                  Caddy Installer Script
#
#   Quick hack by lindenstaub to work with systemd and make the folders/files expected by caddy
#
#   Original version:   https://github.com/caddyserver/getcaddy.com
#   Requires: bash, mv, rm, tr, type, curl/wget, tar (or unzip on OSX and Windows)
#
# This script safely installs Caddy into your PATH (which may require
# password authorization). Use it like this:
#
#	$ curl https://getcaddy.com | bash
#	 or
#	$ wget -qO- https://getcaddy.com | bash
#
# If you want to get Caddy with extra plugins, use -s with a
# comma-separated list of plugin names, like this:
#
#	$ curl https://getcaddy.com | bash -s http.git,http.ratelimit,dns
#
# In automated environments, you may want to run as root.
# If using curl, we recommend using the -fsSL flags.
#
# !!! This script will probably break on any system without systemd. !!!
# Make a pull request if you have a patch to make it init system agnostic.
# https://github.com/lindenstaub/caddy-install.sh
#
#
#                      TROUBLESHOOTING
# Error: caddy.service start request repeated too quickly, refusing to start.
#
# Comment out this line in the /etc/systemctl/system/caddy.service file to see an actual error:
# `Restart=on-failure`
# Then you have to make systemctl see that the file is changed:
# `systemctl daemon-reload`
#
# Or to manually start caddy and see it's output directly
# `sudo -u www-data -h /usr/local/bin/caddy -log stdout -agree=true -conf=/etc/caddy/Caddyfile -root=/var/tmp`

install_caddy()
{
	trap 'echo -e "Aborted, error $? in command: $BASH_COMMAND"; trap ERR; return 1' ERR
	caddy_os="unsupported"
	caddy_arch="unknown"
	caddy_arm=""
	caddy_plugins="$1"
	install_path="/usr/local/bin"

	# Termux on Android has $PREFIX set which already ends with /usr
	if [[ -n "$ANDROID_ROOT" && -n "$PREFIX" ]]; then
		install_path="$PREFIX/bin"
	fi

	# Fall back to /usr/bin if necessary
	if [[ ! -d $install_path ]]; then
		install_path="/usr/bin"
	fi

	# Not every platform has or needs $sudo_cmd (see issue #40)
	((EUID)) && [[ -z "$ANDROID_ROOT" ]] && sudo_cmd="sudo"

	#########################
	# Which OS and version? #
	#########################

	caddy_bin="caddy"
	caddy_dl_ext=".tar.gz"

  # TODO would be nice to make an if to set which init script/system it's using
  # and later install it to the right place
  caddy_init="init/linux-systemd/caddy.service"

	# NOTE: `uname -m` is more accurate and universal than `arch`
	# See https://en.wikipedia.org/wiki/Uname
	unamem="$(uname -m)"
	if [[ $unamem == *aarch64* ]]; then
		caddy_arch="arm64"
	elif [[ $unamem == *64* ]]; then
		caddy_arch="amd64"
	elif [[ $unamem == *86* ]]; then
		caddy_arch="386"
	elif [[ $unamem == *armv5* ]]; then
		caddy_arch="arm"
		caddy_arm="5"
	elif [[ $unamem == *armv6l* ]]; then
		caddy_arch="arm"
		caddy_arm="6"
	elif [[ $unamem == *armv7l* ]]; then
		caddy_arch="arm"
		caddy_arm="7"
	else
		echo "Aborted, unsupported or unknown architecture: $unamem"
		return 2
	fi

	unameu="$(tr '[:lower:]' '[:upper:]' <<<$(uname))"
	if [[ ${unameu} == *DARWIN* ]]; then
		caddy_os="darwin"
		caddy_dl_ext=".zip"
		vers=$(sw_vers)
		version=${vers##*ProductVersion:}
		IFS='.' read OSX_MAJOR OSX_MINOR _ <<<"$version"

		# Major
		if ((OSX_MAJOR < 10)); then
			echo "Aborted, unsupported OS X version (9-)"
			return 3
		fi
		if ((OSX_MAJOR > 10)); then
			echo "Aborted, unsupported OS X version (11+)"
			return 4
		fi

		# Minor
		if ((OSX_MINOR < 5)); then
			echo "Aborted, unsupported OS X version (10.5-)"
			return 5
		fi
	elif [[ ${unameu} == *LINUX* ]]; then
		caddy_os="linux"
	elif [[ ${unameu} == *FREEBSD* ]]; then
		caddy_os="freebsd"
	elif [[ ${unameu} == *OPENBSD* ]]; then
		caddy_os="openbsd"
	elif [[ ${unameu} == *WIN* ]]; then
		# Should catch cygwin
		caddy_os="windows"
		caddy_dl_ext=".zip"
		caddy_bin=$caddy_bin.exe
	else
		echo "Aborted, unsupported or unknown os: $uname"
		return 6
	fi

	########################
	# Download and extract #
	########################

	echo "Downloading Caddy for $caddy_os/$caddy_arch$caddy_arm..."
	caddy_file="caddy_${caddy_os}_$caddy_arch${caddy_arm}_custom$caddy_dl_ext"
	caddy_url="https://caddyserver.com/download/$caddy_os/$caddy_arch$caddy_arm?plugins=$caddy_plugins"
	echo "$caddy_url"

	# Use $PREFIX for compatibility with Termux on Android
  echo $PREFIX
	rm -rf "$PREFIX/tmp/$caddy_file"

	if type -p curl >/dev/null 2>&1; then
		curl -fsSL "$caddy_url" -o "$PREFIX/tmp/$caddy_file"
	elif type -p wget >/dev/null 2>&1; then
		wget --quiet "$caddy_url" -O "$PREFIX/tmp/$caddy_file"
	else
		echo "Aborted, could not find curl or wget"
		return 7
	fi

	echo "Extracting bin..."
	case "$caddy_file" in
		*.zip)    unzip -o "$PREFIX/tmp/$caddy_file" "$caddy_bin" -d "$PREFIX/tmp/" ;;
		*.tar.gz) tar -xzf "$PREFIX/tmp/$caddy_file" -C "$PREFIX/tmp/" "$caddy_bin" ;;
	esac
	chmod +x "$PREFIX/tmp/$caddy_bin"

	echo "Extracting init script..."
	case "$caddy_file" in
		*.zip)    unzip -o "$PREFIX/tmp/$caddy_file" "$caddy_init" -d "$PREFIX/tmp/" ;;
		*.tar.gz) tar -xzf "$PREFIX/tmp/$caddy_file" -C "$PREFIX/tmp/" "$caddy_init" ;;
	esac


  echo $(ls $PREFIX/tmp/)
  read ffff

	# Back up existing caddy, if any
	caddy_cur_ver="$("$caddy_bin" --version 2>/dev/null | cut -d ' ' -f2)"
	if [[ $caddy_cur_ver ]]; then
		# caddy of some version is already installed
		caddy_path="$(type -p "$caddy_bin")"
		caddy_backup="${caddy_path}_$caddy_cur_ver"
		echo "Backing up $caddy_path to $caddy_backup"
		echo "(Password may be required.)"
		$sudo_cmd mv "$caddy_path" "$caddy_backup"
	fi

	echo "Putting caddy in $install_path (may require password)"
	$sudo_cmd mv "$PREFIX/tmp/$caddy_bin" "$install_path/$caddy_bin"
	if setcap_cmd=$(type -p setcap); then
		$sudo_cmd $setcap_cmd cap_net_bind_service=+ep "$install_path/$caddy_bin"
	fi
	$sudo_cmd rm -- "$PREFIX/tmp/$caddy_file"

  # TODO make this init system sensitive
  init_script_path="/etc/systemd/system/"
  echo "Putting init script in $init_script_path"
  $sudo_cmd cp $caddy_init $init_script_path
  $sudo_cmd chown root:root $init_script_path$caddy_init
  $sudo_cmd chmod 644 $init_script_path$caddy_init
  $sudo_cmd systemctl daemon-reload

  # check init script installation
  # TODO make this init system neutral
  # I couldn't make this work right, even though the other grep does work....
  #if [ "$(systemctl status $caddy_init | grep -c could\ not\ be\ found )" -eq 0 ]; then
  #  echo "Init system ready for initing";
  #fi


  # Prepare caddy user
  caddy_user="$caddy_user"
  # and there's probably a better idea than assuming there's not already a user 33...
  if [ $(grep -c $caddy_user /etc/passwd) -eq 0 ]; then
    echo "Making $caddy_user user"
    $sudo_cmd groupadd -g 33 $caddy_user
    $sudo_cmd useradd \
      -g $caddy_user --no-user-group \
      --home-dir /var/www --no-create-home \
      --shell /usr/sbin/nologin \
      --system --uid 33 $caddy_user
  fi



  # Prepare directories for caddy:
  $sudo_cmd mkdir /etc/caddy
  $sudo_cmd chown -R root:$caddy_user /etc/caddy
  $sudo_cmd mkdir /etc/ssl/caddy
  $sudo_cmd chown -R $caddy_user:root /etc/ssl/caddy
  $sudo_cmd chmod 0770 /etc/ssl/caddy
  $sudo_cmd mkdir /var/www
  $sudo_cmd chown www-data:www-data /var/www
  $sudo_cmd chmod 555 /var/www

  # Make a dummy Caddyfile
  $sudo_cmd touch /etc/caddy/Caddyfile
  $sudo_cmd chown www-data:www-data /etc/caddy/Caddyfile
  $sudo_cmd chmod 444 /etc/caddy/Caddyfile

	# check installation
	$caddy_bin --version

	echo "Successfully installed"
  echo "Edit the Caddyfile at /etc/caddy/Caddyfile so that caddy can start"
  echo "See https://caddyserver.com/docs/caddyfile for more information"
  echo ""
  echo "To start caddy:"
  echo "sudo systemctl start caddy.service"
  echo ""
  echo "To enable automatic start on boot:"
  echo "sudo systemctl enable caddy.service"
  echo ""
  echo "A minimum ulimit of 8192 is suggested:"
  echo "sudo ulimit -n 8192"
  echo ""

	trap ERR
	return 0
}

install_caddy "$@"
