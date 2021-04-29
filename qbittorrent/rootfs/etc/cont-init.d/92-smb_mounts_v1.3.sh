#!/usr/bin/with-contenv bashio

####################
# MOUNT SMB SHARES #
####################
if bashio::config.has_value 'networkdisks'; then
    # Mount CIFS Share if configured and if Protection Mode is active
    bashio::log.info 'Mounting smb share(s)...'

    # Define variables 
    MOREDISKS=$(bashio::config 'networkdisks')
    CIFS_USERNAME=$(bashio::config 'cifsusername')
    CIFS_PASSWORD=$(bashio::config 'cifspassword')
    MOUNTED=false

    if bashio::config.has_value 'cifsdomain'; then 
      DOMAIN=",domain=$(bashio::config 'cifsdomain')" 
    else
      DOMAIN=""
    fi
 
    # Mounting disks
    for disk in ${MOREDISKS//,/ }  # Separate comma separated values
    do
      # Clean name of network share
      disk=$(echo $disk | sed "s,/$,,") # Remove / at end of name
      diskname=${disk//\\//} #replace \ with /
      diskname=${diskname##*/} # Get only last part of the name
      # Prepare mount point
      mkdir -p /mnt/$diskname
      chown -R root:root /mnt/$diskname
      
      #Tries to mount with default options
      bashio::log.info "... trying to mount with default options"
      mount -t cifs -o rw,iocharset=utf8,file_mode=0777,dir_mode=0777,username=$CIFS_USERNAME,password=${CIFS_PASSWORD}$DOMAIN $disk /mnt/$diskname 2>ERRORCODE && MOUNTED=true || MOUNTED=false

      #If mounting failed, tries to force uid/gid 0/0
      if [ $MOUNTED = true ]; then
        bashio::log.info "... trying to force uid 0 gid 0"
        mount -t cifs -o rw,iocharset=utf8,file_mode=0777,dir_mode=0777,uid=0,gid=0,forceuid,forcegid,username=$CIFS_USERNAME,password=${CIFS_PASSWORD}$DOMAIN $disk /mnt/$diskname 2>ERRORCODE && MOUNTED=true || MOUNTED=false
      fi

      #If mounting failed, tries to mount as NFS
      if [ $MOUNTED = true ]; then
        bashio::log.info "... mounts as NFS"
        disknfs=$(echo $disk | sed 's/^\///')
        disknfs=$(echo $disknfs | sed 's/^\///')
        mount -t nfs $disknfs /mnt/$diskname 2>ERRORCODE && MOUNTED=true || MOUNTED=false
      fi
      
        # if Fail test different smb and sec versions
      if [ $MOUNTED = false ]; then
        for SMBVERS in ",vers=2.1" ",vers=3.0" ",vers=1.0" ",vers=3.1.1" ",vers=2.0" ",vers=3.0.2"
        do
           bashio::log.warning "... trying to mount with $SMBVERS"
           mount -t cifs -o rw,iocharset=utf8,file_mode=0777,dir_mode=0777,username=$CIFS_USERNAME,password=${CIFS_PASSWORD}$DOMAIN$SMBVERS $disk /mnt/$diskname 2>/dev/null && MOUNTED=true && break  || MOUNTED=false
           for SECVERS in ",sec=ntlmi" ",sec=ntlmv2" ",sec=ntlmv2i" ",sec=ntlmssp" ",sec=ntlmsspi" ",sec=ntlm" ",sec=krb5i" ",sec=krb5"
           do
                bashio::log.warning "... trying to mount with $SMBVERS $SECVERS"
                mount -t cifs -o rw,iocharset=utf8,file_mode=0777,dir_mode=0777,username=$CIFS_USERNAME,password=${CIFS_PASSWORD}$DOMAIN$SMBVERS$SECVERS $disk /mnt/$disk name 2>/dev/null && MOUNTED=true && break 2 && break || MOUNTED=false
           done
        done
      fi

      # Messages
      if [ $MOUNTED = true ]; then
        #Test write permissions
        touch /mnt/$diskname/testaze && rm /mnt/$diskname/testaze && bashio::log.info "... $disk successfully mounted to /mnt/$diskname" || bashio::log.fatal "Unable to write in the shared disk. Please check UID/GID for permissions, and if the share is rw" 
      else
        # message if still fail
        bashio::log.fatal "Unable to mount $disk to /mnt/$diskname with username $CIFS_USERNAME, $CIFS_PASSWORD. Please check your remote share path, username, password, domain, try putting 0 in UID and GID" # Mount share
        bashio::log.fatal "Error read : $(<ERRORCODE)" # Mount share
        rm ERRORCODE
      fi

    done
fi
