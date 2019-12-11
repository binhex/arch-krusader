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
mv /tmp/scripts-master/shell/arch/docker/*.sh /usr/local/bin/

# pacman packages
####

# call pacman db and package updater script
source upd.sh

# define pacman packages
pacman_packages="krusader p7zip unarj xz zip lhasa arj unace ntfs-3g kde-cli-tools kio-extras kdiff3 keditbookmarks kompare konsole krename ktexteditor breeze-icons"

# install compiled packages using pacman
if [[ ! -z "${pacman_packages}" ]]; then
	pacman -S --needed $pacman_packages --noconfirm
fi

# aur packages
####

# define aur packages
aur_packages="websockify"

# call aur install script (arch user repo)
source aur.sh

# config novnc
###

# overwrite novnc 16x16 icon with application specific 16x16 icon (used by bookmarks and favorites)
cp /home/nobody/novnc-16x16.png /usr/share/webapps/novnc/app/images/icons/

# config krusader
####

cat <<'EOF' > /tmp/config_heredoc

# delme 10/12/2020
# this code moves any existing krusader config over to the new /config/home folder
cp -R /config/krusader/.config/ /config/home/ && rm -rf /config/krusader/.config
cp -R /config/krusader/.local/ /config/home/ && rm -rf /config/krusader/.local
# /delme 10/12/2020

# the below code changes the temp folder for krusader to the value defined via the env var
# TEMP_FOLDER, if not defined it will use the default value (see env vars heredoc)

# path to krusader config file
krusader_config_path="/config/home/.config/krusaderrc"

# create the krusader config file (will not exist on first run)
touch "${krusader_config_path}"

# search for [General] section (may not be defined)
grep -q "^\[General\]" "${krusader_config_path}"

if [[ "${?}" -eq 0 ]]; then
    # search for Temp Directory
    grep -q "^Temp Directory" "${krusader_config_path}"

    if [[ "${?}" -eq 0 ]]; then
        # overwrite defined value for Temp Directory
        sed -i "s~^Temp Directory.*~Temp Directory=${TEMP_FOLDER}~g" "${krusader_config_path}"
    else
        # append Temp Directory after [General] section
        sed -i "/\[General\]/a Temp Directory=${TEMP_FOLDER}" "${krusader_config_path}"
    fi

else
    # append [General] section and Temp Directory to config file
    printf "\n[General]\nTemp Directory=${TEMP_FOLDER}\n" >> "${krusader_config_path}"
fi

# finally make the temp directory
mkdir -p "${TEMP_FOLDER}"

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
export TEMP_FOLDER=$(echo "${TEMP_FOLDER}" | sed -e 's~^[ \t]*~~;s~[ \t]*$~~')
if [[ ! -z "${TEMP_FOLDER}" ]]; then
	echo "[info] TEMP_FOLDER defined as '${TEMP_FOLDER}'" | ts '%Y-%m-%d %H:%M:%.S'
else
	export TEMP_FOLDER="/config/krusader/tmp"
	echo "[info] TEMP_FOLDER not defined, defaulting to '${TEMP_FOLDER}'" | ts '%Y-%m-%d %H:%M:%.S'
fi
EOF

# replace env vars placeholder string with contents of file (here doc)
sed -i '/# ENVVARS_PLACEHOLDER/{
	s/# ENVVARS_PLACEHOLDER//g
	r /tmp/envvars_heredoc
}' /usr/local/bin/init.sh
rm /tmp/envvars_heredoc

# container perms
####

# define comma separated list of paths
install_paths="/tmp,/usr/share/themes,/home/nobody,/usr/share/webapps/novnc,/usr/share/krusader,/usr/share/applications,/etc/xdg"

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
previous_puid=\$(cat "/root/puid" 2>/dev/null || true)
previous_pgid=\$(cat "/root/pgid" 2>/dev/null || true)

# if first run (no puid or pgid files in /tmp) or the PUID or PGID env vars are different
# from the previous run then re-apply chown with current PUID and PGID values.
if [[ ! -f "/root/puid" || ! -f "/root/pgid" || "\${previous_puid}" != "\${PUID}" || "\${previous_pgid}" != "\${PGID}" ]]; then

	# set permissions inside container - Do NOT double quote variable for install_paths otherwise this will wrap space separated paths as a single string
	chown -R "\${PUID}":"\${PGID}" ${install_paths}

fi

# write out current PUID and PGID to files in /root (used to compare on next run)
echo "\${PUID}" > /root/puid
echo "\${PGID}" > /root/pgid

# env var required to find qt plugins when starting krusader
export QT_QPA_PLATFORM_PLUGIN_PATH=/usr/lib/qt/plugins/platforms

# env vars required to enable menu icons for krusader (also requires breeze-icons package)
export KDE_SESSION_VERSION=5 KDE_FULL_SESSION=true
EOF

# replace permissions placeholder string with contents of file (here doc)
sed -i '/# PERMISSIONS_PLACEHOLDER/{
	s/# PERMISSIONS_PLACEHOLDER//g
	r /tmp/permissions_heredoc
}' /usr/local/bin/init.sh
rm /tmp/permissions_heredoc

# env vars
####

# cleanup
cleanup.sh
