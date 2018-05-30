#!/bin/bash

# exit script if return code != 0
set -e

# build scripts
####

# download build scripts from github
curl --connect-timeout 5 --max-time 600 --retry 5 --retry-delay 0 --retry-max-time 60 -o /tmp/scripts-master.zip -L https://github.com/binhex/scripts/archive/master.zip

# unzip build scripts
unzip /tmp/scripts-master.zip -d /tmp

# move shell scripts to /root
mv /tmp/scripts-master/shell/arch/docker/*.sh /root/

# pacman packages
####

# define pacman packages
pacman_packages="krusader p7zip unarj unzip unrar xz zip lhasa arj unace ntfs-3g kde-cli-tools kuiserver kio-extras kdiff3 keditbookmarks kompare konsole krename ktexteditor breeze-icons"

# install compiled packages using pacman
if [[ ! -z "${pacman_packages}" ]]; then
	pacman -S --needed $pacman_packages --noconfirm
fi

# aor packages
####

# define arch official repo (aor) packages
aor_packages=""

# call aor script (arch official repo)
source /root/aor.sh

# aur packages
####

# define aur packages
aur_packages="rar"

# call aur install script (arch user repo)
source /root/aur.sh

# config novnc
###

# overwrite novnc favicon with application favicon
cp /home/nobody/favicon.ico /usr/share/novnc/

# config krusader
####

cat <<'EOF' > /tmp/config_heredoc
# if /home/nobody/.config/ exists in container then suffix with -backup, this is used 
# later on as a way of getting back to defaults if /config/krusader/.config is deleted
# note we check that the folder is not a soft link (soft links persist reboots)
if [[ -d "/home/nobody/.config" && ! -L "/home/nobody/.config" ]]; then
	echo "[info] /home/nobody/.config folder storing Krusader general settings already exists, renaming folder..."
	mv /home/nobody/.config /home/nobody/.config-backup
fi

# if /config/krusader/.config doesnt exist then restore from backup (see note above)
if [[ ! -d "/config/krusader/.config" ]]; then

	if [[ -d "/home/nobody/.config-backup" && ! -L "/home/nobody/.config-backup" ]]; then
		echo "[info] /config/krusader/.config folder storing Krusader general settings does not exist, copying defaults..."
		cp -R /home/nobody/.config-backup /config/krusader/.config
	fi

else

	echo "[info] /config/krusader/.config folder storing Krusader general settings already exists, skipping copy"

fi

# create soft link to /home/nobody/.config folder storing krusader general settings
# note we do -L check as soft links are persistent between reboots
if [[ ! -L "/home/nobody/.config" ]]; then
	echo "[info] Creating soft link from /config/krusader/.config to /home/nobody/.config..."
	mkdir -p /config/krusader/.config ; rm -rf /home/nobody/.config/ ; ln -sf /config/krusader/.config /home/nobody/.config
fi

# create soft link to /home/nobody/.local folder storing krusader ui and bookmarks
# note we do -L check as soft links are persistent between reboots
if [[ ! -L "/home/nobody/.local" ]]; then
	echo "[info] Creating soft link from /config/krusader/.local to /home/nobody/.local..."
	mkdir -p /config/krusader/.local ; rm -rf /home/nobody/.local/ ; ln -sf /config/krusader/.local /home/nobody/.local
fi
EOF

# replace config placeholder string with contents of file (here doc)
sed -i '/# CONFIG_PLACEHOLDER/{
	s/# CONFIG_PLACEHOLDER//g
	r /tmp/config_heredoc
}' /home/nobody/start.sh
rm /tmp/config_heredoc

cat <<'EOF' > /tmp/startcmd_heredoc
# launch krusader (we cannot simply call /usr/bin/krusader otherwise it wont run on startup)
# note failure to launch krusader in the below manner will result in the classic xcb missing error
dbus-run-session -- krusader
EOF

# replace startcmd placeholder string with contents of file (here doc)
sed -i '/# STARTCMD_PLACEHOLDER/{
	s/# STARTCMD_PLACEHOLDER//g
	r /tmp/startcmd_heredoc
}' /home/nobody/start.sh
rm /tmp/startcmd_heredoc

# config openbox
####

cat <<'EOF' > /tmp/menu_heredoc
	<item label="Krusader">
	<action name="Execute">
	  <command>dbus-launch krusader</command>
	  <startupnotify>
		<enabled>yes</enabled>
	  </startupnotify>
	</action>
	</item>
EOF

# replace menu placeholder string with contents of file (here doc)
sed -i '/<!-- APPLICATIONS_PLACEHOLDER -->/{
	s/<!-- APPLICATIONS_PLACEHOLDER -->//g
	r /tmp/menu_heredoc
}' /home/nobody/.config/openbox/menu.xml
rm /tmp/menu_heredoc

# env vars
####

cat <<'EOF' > /tmp/envvars_heredoc
export WEBPAGE_TITLE=$(echo "${WEBPAGE_TITLE}" | sed -e 's~^[ \t]*~~;s~[ \t]*$~~')
if [[ ! -z "${WEBPAGE_TITLE}" ]]; then
	echo "[info] WEBPAGE_TITLE defined as '${WEBPAGE_TITLE}'" | ts '%Y-%m-%d %H:%M:%.S'
fi

export TEMP_FOLDER=$(echo "${TEMP_FOLDER}" | sed -e 's~^[ \t]*~~;s~[ \t]*$~~')
if [[ ! -z "${TEMP_FOLDER}" ]]; then
	echo "[info] TEMP_FOLDER defined as '${TEMP_FOLDER}'" | ts '%Y-%m-%d %H:%M:%.S'
else
	export TEMP_FOLDER="/config/krusader/tmp"
	echo "[info] TEMP_FOLDER not defined, defaulting to '${TEMP_FOLDER}'" | ts '%Y-%m-%d %H:%M:%.S'
fi
# create temp folder
mkdir -p "${TEMP_FOLDER}"
EOF

# replace env vars placeholder string with contents of file (here doc)
sed -i '/<!-- ENVVARS_PLACEHOLDER -->/{
	s/<!-- ENVVARS_PLACEHOLDER -->//g
	r /tmp/envvars_heredoc
}' /root/init.sh
rm /tmp/envvars_heredoc

# container perms
####

# define comma separated list of paths
install_paths="/tmp,/usr/share/themes,/home/nobody,/usr/share/novnc,/usr/share/krusader,/usr/share/applications,/etc/xdg"

# split comma separated string into list for install paths
IFS=',' read -ra install_paths_list <<< "${install_paths}"

# process install paths in the list
for i in "${install_paths_list[@]}"; do

	# confirm path(s) exist, if not then exit
	if [[ ! -d "${i}" ]]; then
		echo "[crit] Path '${i}' does not exist, exiting build process..." ; exit 1
	fi

done

# convert comma separated string of install paths to space separated, required for chmod/chown processing
install_paths=$(echo "${install_paths}" | tr ',' ' ')

# set permissions for container during build - Do NOT double quote variable for install_paths otherwise this will wrap space separated paths as a single string
chmod -R 775 ${install_paths}

# create file with contents of here doc, note EOF is NOT quoted to allow us to expand current variable 'install_paths'
# we use escaping to prevent variable expansion for PUID and PGID, as we want these expanded at runtime of init.sh
cat <<EOF > /tmp/permissions_heredoc

# get previous puid/pgid (if first run then will be empty string)
previous_puid=\$(cat "/tmp/puid" 2>/dev/null || true)
previous_pgid=\$(cat "/tmp/pgid" 2>/dev/null || true)

# if first run (no puid or pgid files in /tmp) or the PUID or PGID env vars are different
# from the previous run then re-apply chown with current PUID and PGID values.
if [[ ! -f "/tmp/puid" || ! -f "/tmp/pgid" || "\${previous_puid}" != "\${PUID}" || "\${previous_pgid}" != "\${PGID}" ]]; then

	# set permissions inside container - Do NOT double quote variable for install_paths otherwise this will wrap space separated paths as a single string
	chown -R "\${PUID}":"\${PGID}" ${install_paths}

fi

# write out current PUID and PGID to files in /tmp (used to compare on next run)
echo "\${PUID}" > /tmp/puid
echo "\${PGID}" > /tmp/pgid

# env var required to find qt plugins when starting krusader
export QT_QPA_PLATFORM_PLUGIN_PATH=/usr/lib/qt/plugins/platforms

# env vars required to enable menu icons for krusader (also requires breeze-icons package)
export KDE_SESSION_VERSION=5 KDE_FULL_SESSION=true
EOF

# replace permissions placeholder string with contents of file (here doc)
sed -i '/# PERMISSIONS_PLACEHOLDER/{
	s/# PERMISSIONS_PLACEHOLDER//g
	r /tmp/permissions_heredoc
}' /root/init.sh
rm /tmp/permissions_heredoc

# env vars
####

# cleanup
yes|pacman -Scc
rm -rf /usr/share/locale/*
rm -rf /usr/share/man/*
rm -rf /usr/share/gtk-doc/*
rm -rf /tmp/*
