FROM binhex/arch-int-gui:latest
MAINTAINER binhex

# additional files
##################

# add install and packer bash script
ADD build/root/*.sh /root/

# add pre-configured config files for deluge
ADD config/nobody/ /home/nobody/

# install app
#############

# make executable and run bash scripts to install app
RUN chmod +x /root/*.sh && \
	/bin/bash /root/install.sh

# docker settings
#################

# map /config to host defined config path (used to store configuration from app)
VOLUME /config

# map /data to host defined config path (used to store data from app)
VOLUME /data

# set permissions
#################

# run script to set uid, gid and permissions
CMD ["/bin/bash", "/usr/local/bin/init.sh"]
