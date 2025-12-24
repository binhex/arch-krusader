#!/bin/bash

# exit script if return code != 0
set -e

# app name from buildx arg, used in healthcheck to identify app and monitor correct process
APPNAME="${1}"
shift

# release tag name from buildx arg, stripped of build ver using string manipulation
RELEASETAG="${1}"
shift

# target arch from buildx arg
TARGETARCH="${1}"
shift

if [[ -z "${APPNAME}" ]]; then
	echo "[warn] App name from build arg is empty, exiting script..."
	exit 1
fi

if [[ -z "${RELEASETAG}" ]]; then
	echo "[warn] Release tag name from build arg is empty, exiting script..."
	exit 1
fi

if [[ -z "${TARGETARCH}" ]]; then
	echo "[warn] Target architecture name from build arg is empty, exiting script..."
	exit 1
fi

# write APPNAME and RELEASETAG to file to record the app name and release tag used to build the image
echo -e "export APPNAME=${APPNAME}\nexport IMAGE_RELEASE_TAG=${RELEASETAG}\n" >> '/etc/image-build-info'

# ensure we have the latest builds scripts
refresh.sh

# pacman packages
####

# call pacman db and package updater script
source upd.sh

# define pacman packages
pacman_packages="krusader 7zip unarj xz zip lhasa arj unace ntfs-3g kde-cli-tools kio-extras kdiff3 keditbookmarks kompare konsole krename ktexteditor breeze-icons"

# install compiled packages using pacman
if [[ -n "${pacman_packages}" ]]; then
	# arm64 currently targetting aor not archive, so we need to update the system first
	if [[ "${TARGETARCH}" == "arm64" ]]; then
		pacman -Syu --noconfirm
	fi
	pacman -S --needed $pacman_packages --noconfirm
fi

# config novnc
###

# overwrite novnc 16x16 icon with application specific 16x16 icon (used by bookmarks and favorites)
cp /home/nobody/novnc-16x16.png /usr/share/webapps/novnc/app/images/icons/

# config krusader
####

cat <<'EOF' > /tmp/config_heredoc


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
}' /usr/local/bin/start.sh
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
}' /usr/local/bin/start.sh
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
	export TEMP_FOLDER="/config/home/.config/krusader/tmp"
	echo "[info] TEMP_FOLDER not defined, defaulting to '${TEMP_FOLDER}'" | ts '%Y-%m-%d %H:%M:%.S'
fi
EOF

# replace env vars placeholder string with contents of file (here doc)
sed -i '/# ENVVARS_PLACEHOLDER/{
	s/# ENVVARS_PLACEHOLDER//g
	r /tmp/envvars_heredoc
}' /usr/bin/init.sh
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

# In install.sh heredoc, replace the chown section:
cat <<EOF > /tmp/permissions_heredoc
install_paths="${install_paths}"
EOF

# replace permissions placeholder string with contents of file (here doc)
sed -i '/# PERMISSIONS_PLACEHOLDER/{
    s/# PERMISSIONS_PLACEHOLDER//g
    r /tmp/permissions_heredoc
}' /usr/bin/init.sh
rm /tmp/permissions_heredoc

# cleanup
cleanup.sh
