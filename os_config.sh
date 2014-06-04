#!/bin/sh
#
# Orc Software's Linux server OS customization script
# Version 1.0, by alessandro.cherubin@orcsoftware.com 2011-05-03
# Tested OK on RHEL6
#
# Version history:
# 1.0: 2011-05-03, first release
# 1.1: 2012-09-12, added CFS kernel tuning configurations (kernel.sched_*)
# 1.2: 2013-08-12, removes bc dependency
#


VERSION=1.1

COREDUMPDIR="/var/cores"
MAXFILEDESCRIPTORSPERUSER="63536"
GLOBALMAXFILEDESCRIPTORS=$((${MAXFILEDESCRIPTORSPERUSER} * 10))
BASSHELLTEMPLATE="./bashrc_template.txt"

ORCUSER="orc"
ORCGROUP=${ORCUSER}
ORCUSERID="7654"
ORCGROUPID=${ORCUSERID}
ORCPASSWORD="orc1234"
ORC_ETC="/etc/orc"
ORC_CONF="${ORC_ETC}/orc.conf"
ORCHOMEDIR=${ORC_ETC}
ORCRELEASEDIR="/orcreleases"
#ORCRELEASEDIR="/opt/orc"
ORCBACKUPDIR="/orcbackup"

INFORMIXUSER="informix"
INFORMIXGROUP=${INFORMIXUSER}
INFORMIXUSERID="700"
INFORMIXGROUPID=${INFORMIXUSERID}
INFORMIXPASSWORD="ids2000"
INFORMIXDIR="/opt/informix"
INFORMIXHOMEDIR=${INFORMIXDIR}
INFORMIXPORT="9000"

#
# Procedure: show help
#
help()
{
        echo "** (c) Orc Software - `basename $0` (v.$VERSION) ** "
        echo ""
        echo "Utility to perform operating system customizations for a brand new RHEL6 Linux server."
        echo ""
        echo "Usage: `basename $0` [ -f | -h ]"
        echo "       -f    Force non-interactive execution"
        echo "       -h    Help, show this message"
        echo ""
}

#
# Procedure: read interactive [Y/N] answer from standard input
#
read_answer()
{
    ANSWER=""
    if [ ${FORCE} = "N" ]; then # interactive
        while [ ! "${ANSWER}" = "Y" ] && [ ! "${ANSWER}" = "N" ]; do
            /bin/echo "  Continue with this operation? [Y/N]"
            read ANSWER
            ANSWER=`/bin/echo "${ANSWER}" | tr "[:lower:]" "[:upper:]" `
        done
    else                        # non-interactive
        ANSWER="Y"
    fi
}

#
# Procedure: read IP address information from standard input
#
read_ip_answer()
{
    IPANSWER=""
    CORRECT="N"
    while [ ! ${CORRECT} = "Y" ]; do
        /bin/echo "Please enter the IP address of the server's primary network interface:"
        read IPANSWER
        NUMFIELDS=`/bin/echo ${IPANSWER} | awk -F"." '{ print NF }'` # count number of fields in IPV4 address
        if [ ! ${NUMFIELDS} -eq "4" ]; then
            CORRECT="N"
            echo "Wrong IP address format: incorrect number of fields for IPv4."
        else
            IPANSWER=`/bin/echo ${IPANSWER} | sed 's/\./ /g'`
            for FIELD in $IPANSWER; do
                ISNUMBER=`echo "$FIELD" | awk '{ if (/^[0-9]+$/) print "Y"; else print "N" }' `    # check each field is a number
                if [ ! ${ISNUMBER} = "Y" ]; then
                    CORRECT="N"
                    echo "Wrong IP address format: all fields should be numeric."
                    break
                else
                    if [ ! ${FIELD} -le "254" ]; then
                        CORRECT="N"
                        echo "Wrong IP address format: at least one number is too large."
                        break
                    else
                        CORRECT="Y"
			IPANSWER=`/bin/echo ${IPANSWER} | sed 's/ /\./g'`
                        #echo "OK"
                    fi
                fi
            done 
        fi
    done
}

#
# Procedure: perform OS configurations
#
os_customize()
{
    /bin/echo ""
    /bin/echo "* [/etc/inittab]: set default runlevel to 3 (networked, multiuser, no GUI)"
    read_answer
    if [ "${ANSWER}" = "Y" ]; then
         RUNLEVEL=`/bin/grep ":initdefault:" /etc/inittab | awk -F":" '{ print $2 }'`
         if [ ! ${RUNLEVEL} -eq "3" ]; then
              /bin/mv /etc/inittab /etc/inittab.orig
              /bin/cat /etc/inittab.orig | sed "s/id:${RUNLEVEL}:initdefault:/id:3:initdefault:/g" > /etc/inittab
         fi
    fi


    /bin/echo ""
    /bin/echo "* [iptables]: stop and disable of firewall service"
    read_answer
    if [ "${ANSWER}" = "Y" ]; then
        /sbin/service iptables stop
        /sbin/chkconfig --level 0123456 iptables off
        /sbin/chkconfig --list iptables
    fi


    /bin/echo ""
    /bin/echo "* [auditd]: stop and disable of LAUS, Linux audit service"
    read_answer
    if [ "${ANSWER}" = "Y" ]; then
        /sbin/service auditd stop
        /sbin/chkconfig --level 0123456 auditd off
        /sbin/chkconfig --list auditd 
    fi


    /bin/echo ""
    /bin/echo "* [vsftpd]: enable and start Very Secure FTP service"
    read_answer
    if [ "${ANSWER}" = "Y" ]; then
        /sbin/chkconfig --level 345 vsftpd on
        /sbin/service vsftpd start
        /sbin/chkconfig --list vsftpd
    fi


    /bin/echo ""
    /bin/echo "* [/etc/selinux/config]: disable Security Enhanced (SE) Linux"
    read_answer
    if [ "${ANSWER}" = "Y" ]; then
        /bin/mv /etc/selinux/config /etc/selinux/config.orig 
        /bin/cat /etc/selinux/config.orig | sed 's/SELINUX=enforcing/SELINUX=disabled/g' > /etc/selinux/config
        /bin/grep "^SELINUX=" /etc/selinux/config
    fi


    /bin/echo ""
    /bin/echo "* [/var/log/messages]: fix of OS logfile permissions"
    read_answer
    if [ "${ANSWER}" = "Y" ]; then
        /bin/chmod a+r /var/log/messages
        /bin/ls -la /var/log/messages
    fi


    /bin/echo ""
    /bin/echo "* [/etc/sysctl.conf, /etc/security/limits.conf]: configure core files to dump into '${COREDUMPDIR}' as 'core_<host>_<command>.<pid>'"
    read_answer
    if [ "${ANSWER}" = "Y" ]; then
        # creation of cores' destination directory
        /bin/mkdir -p ${COREDUMPDIR}
        /bin/chmod 5777 ${COREDUMPDIR}
        /bin/echo "   - '${COREDUMPDIR}' core destination directory created"
        # configuration of cores' dump directory and filename pattern in /etc/sysctl.conf
        /bin/echo "# Orc Software: dump cores into '/var/cores' using 'core_<host>_<command>.<pid>' naming scheme" >> /etc/sysctl.conf
        # /bin/echo "kernel.core_uses_pid = 1" >> /etc/sysctl.conf  # default in RHEL6
        /bin/echo "kernel.core_pattern=${COREDUMPDIR}/core_%h_%e.%p" >> /etc/sysctl.conf
	/bin/echo "${COREDUMPDIR}/core_%h_%e.%p" > /proc/sys/kernel/core_pattern
        /sbin/sysctl -p > /dev/null 2>&1
        /bin/echo "   - '/etc/sysctl.conf' configurations for dump directory and filename pattern added and activated"
        # configuration of cores' max size in /etc/security/limits.conf
        /bin/echo "# Orc Software: system global core file size limits - 1000 GB (infinite)" >> /etc/security/limits.conf
        /bin/echo "*             soft      core         1000000000"  >> /etc/security/limits.conf
        /bin/echo "*             hard      core         1000000000"  >> /etc/security/limits.conf
        /sbin/sysctl -p > /dev/null 2>&1
        /bin/echo "   - '/etc/security/limits.conf' configurations for max core file size added and activated"
        # crontab job to keep core destination directory clean
        /usr/bin/crontab -l > /tmp/root_crontab.$$ 2> /dev/null2> /dev/null
        /bin/echo "# Orc Software: automatic deletion of core files older than 21 days from '${COREDUMPDIR}'" >> /tmp/root_crontab.$$
        /bin/echo "55 23 * * * /usr/bin/find ${COREDUMPDIR} -name \"core_*\" -mtime +21 -exec /bin/rm {} \;" >> /tmp/root_crontab.$$
        /usr/bin/crontab /tmp/root_crontab.$$
        /bin/rm -f /tmp/root_crontab.$$ > /dev/null 2>&1
        /bin/echo "   - crontab job to keep '${COREDUMPDIR}' clean was added"
    fi

    
    /bin/echo ""
    /bin/echo "* [/etc/security/limits.conf]: increase number of file descriptors for '${ORCUSER}' user"
    read_answer
    if [ "${ANSWER}" = "Y" ]; then
        /bin/echo "# Orc Software: increase limit of file descriptors for '${ORCUSER}' user to '${MAXFILEDESCRIPTORSPERUSER}'" >> /etc/security/limits.conf
        /bin/echo "${ORCUSER}         soft      nofile         ${MAXFILEDESCRIPTORSPERUSER}" >> /etc/security/limits.conf
        /bin/echo "${ORCUSER}         hard      nofile         ${MAXFILEDESCRIPTORSPERUSER}" >> /etc/security/limits.conf
        /sbin/sysctl -p > /dev/null 2>&1
    fi


    /bin/echo ""
    /bin/echo "* [/etc/sysctl.conf]: increase global limit of file descriptors (for all users) to ${GLOBALMAXFILEDESCRIPTORS}"
    read_answer
    if [ "${ANSWER}" = "Y" ]; then
        /bin/echo "# Orc Software: increase global limit of file descriptors (for all users)" >> /etc/sysctl.conf
        /bin/echo "fs.file-max=${GLOBALMAXFILEDESCRIPTORS}" >> /etc/sysctl.conf
        /sbin/sysctl -p > /dev/null 2>&1
    fi


    /bin/echo ""
    /bin/echo "* [/etc/sysctl.conf]: configure CFS kernel for multi-threading"
    read_answer
    if [ "${ANSWER}" = "Y" ]; then
        /bin/echo "# Orc: configure CFS kernel for multi-threading" >> /etc/sysctl.conf
        /bin/echo "kernel.sched_compat_yield=1" >> /etc/sysctl.conf
        /bin/echo "kernel.sched_tunable_scaling=0" >> /etc/sysctl.conf
        /bin/echo "kernel.sched_min_granularity_ns=10000000" >> /etc/sysctl.conf
        /bin/echo "kernel.sched_latency_ns=80000000" >> /etc/sysctl.conf
        /bin/echo "kernel.sched_wakeup_granularity_ns=10000000" >> /etc/sysctl.conf
        
        /sbin/sysctl -p > /dev/null 2>&1
    fi

    /bin/echo ""
    /bin/echo "* [/etc/skel/.bashrc] create standard initialization file for Bash shell"
    read_answer
    if [ "${ANSWER}" = "Y" ]; then
        if [ -r ${BASSHELLTEMPLATE} ]; then
            /bin/mv /etc/skel/.bash_profile  /etc/skel/.bash_profile.original
            /bin/mv /etc/skel/.bashrc  /etc/skel/.bashrc.original
            /bin/cp ${BASSHELLTEMPLATE} /etc/skel/.bashrc
            /bin/ln -s /etc/skel/.bashrc /etc/skel/.bash_profile
        else
            /bin/echo "ERROR: '${BASSHELLTEMPLATE}' template file not found!" 
        fi
    fi

    /bin/echo ""
    /bin/echo "* [/etc/skel/.toprc] prepare initialization file for 'top' command"
    read_answer
    if [ "${ANSWER}" = "Y" ]; then
        /bin/echo "RCfile for \"top with windows\"" >> /etc/skel/.toprc
        /bin/echo "Id:a, Mode_altscr=0, Mode_irixps=0, Delay_time=3.000, Curwin=0" >> /etc/skel/.toprc
    fi

# RHEL6 already puts physical network interface's address into hosts file
#    /bin/echo ""
#    /bin/echo "* [/etc/hosts] associate hostname to a physical network interface address" 
#    read_answer
#    if [ "${ANSWER}" = "Y" ]; then
#        #INTERFACEIP=`/sbin/ifconfig -a | /bin/grep "inet addr" | /bin/grep -v "127.0.0.1"  | /usr/bin/head -1 | /bin/awk -F":" '{ print $2 }' | /bin/awk '{ print $1 }'`
#        read_ip_answer
#        THISHOSTNAME=`hostname`
#	/bin/mv  /etc/hosts  /etc/hosts.orig 
#	/bin/cat  /etc/hosts.orig | sed "s/${THISHOSTNAME}//g" >  /etc/hosts  # strip off hostname from hosts file
#        echo "${IPANSWER}       ${THISHOSTNAME}" >> /etc/hosts
#    fi

}

#
# Procedure: create and configure 'informix' user
#
create_informix_user()
{
    /bin/echo ""
    /bin/echo "* Create '${INFORMIXUSER}' home directory, group and user"
    read_answer
    if [ "${ANSWER}" = "Y" ]; then
       /bin/echo "   - creating '${INFORMIXHOMEDIR}' directory"
       /bin/mkdir -p ${INFORMIXHOMEDIR} > /dev/null 2>&1
       /bin/cp /etc/skel/.bashrc ${INFORMIXHOMEDIR} > /dev/null 2>&1
       /bin/ln -s ${INFORMIXHOMEDIR}/.bashrc ${INFORMIXHOMEDIR}/.bash_profile > /dev/null 2>&1
       /bin/chown -R ${INFORMIXUSERID}:${INFORMIXGROUPID} ${INFORMIXHOMEDIR}
       /bin/echo "   - creating '${INFORMIXGROUP}' group with ID ${INFORMIXGROUPID}"
       /usr/sbin/groupadd -g ${INFORMIXGROUPID} ${INFORMIXGROUP}
       /bin/echo "   - creating '${INFORMIXUSER}' user with ID ${INFORMIXUSERID} and '${INFORMIXHOMEDIR}' as home directory"
       /usr/sbin/useradd -u ${INFORMIXUSERID} -g ${INFORMIXGROUP} -d ${INFORMIXHOMEDIR} -s /bin/bash ${INFORMIXUSER} 2> /dev/null
       /bin/echo "   - setting '${INFORMIXUSER}' user password to \"${INFORMIXPASSWORD}\" (remember to change it afterwards)"
       /bin/echo ${INFORMIXPASSWORD} | /usr/bin/passwd --stdin ${INFORMIXUSER} > /dev/null 2>&1
       /bin/echo "   > ID: `/usr/bin/id ${INFORMIXUSER}`"
       /bin/echo "   > GROUP: `/usr/bin/groups ${INFORMIXUSER}`"
    fi
}


#
# Procedure: create and configure 'orc' user
#
create_orc_user()
{
    /bin/echo ""
    /bin/echo "* Create '${ORCUSER}' home directory, group and user"
    read_answer
    if [ "${ANSWER}" = "Y" ]; then
        /bin/echo "*  Creating '${ORCUSER}' homedir, group and user"
        /bin/echo "   - creating '${ORCHOMEDIR}' directory"
        /bin/mkdir -p ${ORCHOMEDIR} > /dev/null 2>&1
	    /bin/cp /etc/skel/.bashrc ${ORCHOMEDIR} > /dev/null 2>&1
        /bin/ln -s ${ORCHOMEDIR}/.bashrc ${ORCHOMEDIR}/.bash_profile > /dev/null 2>&1
        /bin/chown -R ${ORCUSERID}:${ORCGROUPID} ${ORCHOMEDIR}
        /bin/echo "   - creating '${ORCRELEASEDIR}' directory"
        /bin/mkdir -p ${ORCRELEASEDIR} > /dev/null 2>&1
        /bin/chown -R ${ORCUSERID}:${ORCGROUPID} ${ORCRELEASEDIR}
        /bin/echo "   - creating '${ORCBACKUPDIR}' directory"
        /bin/mkdir -p ${ORCBACKUPDIR} > /dev/null 2>&1
        /bin/chown -R ${ORCUSERID}:${ORCGROUPID} ${ORCBACKUPDIR}
        /bin/echo "   - creating '${ORCGROUP}' group with ID ${ORCGROUPID}"
        /usr/sbin/groupadd -g ${ORCGROUPID} ${ORCGROUP}
        /bin/echo "   - creating '${ORCUSER}' user with ID ${ORCUSERID} and '${ORCHOMEDIR}' as home directory"
        /usr/bin/groups ${INFORMIXUSER} > /dev/null 2>&1  # check if informix group exists
        if [ "$?" -eq "0" ]; then # if informix group exists, add orc user to that group as well
            /usr/sbin/useradd -u ${ORCUSERID} -g ${ORCGROUP} -G ${INFORMIXGROUP} -d ${ORCHOMEDIR} -s /bin/bash ${ORCUSER} 2> /dev/null
        else
            /usr/sbin/useradd -u ${ORCUSERID} -g ${ORCGROUP} -d ${ORCHOMEDIR} -s /bin/bash ${ORCUSER} 2> /dev/null
        fi
        /bin/echo "   - setting '${ORCUSER}' user password to \"${ORCPASSWORD}\" (remember to change it afterwards)"
        /bin/echo ${ORCPASSWORD} | /usr/bin/passwd --stdin ${ORCUSER} > /dev/null 2>&1
        /bin/echo "   > ID: `/usr/bin/id ${ORCUSER}`"
        /bin/echo "   > GROUP: `/usr/bin/groups ${USER}`"
    fi
}

#
# Procedure: perform OS customizations that are specific for Informix. 
# This routine is skipped when the database server is not to be installed locally.
#
os_customize_informix()
{
    /bin/echo ""
    /bin/echo "* [/etc/sysctl.conf]: configure shared memory parameters for Informix"
    read_answer
    if [ "${ANSWER}" = "Y" ]; then
        /bin/echo "# Orc Software: shared memory configuration for Informix" >> /etc/sysctl.conf
        /bin/echo "kernel.shmmni = 128" >> /etc/sysctl.conf
        /bin/echo "kernel.shmall = 4194304" >> /etc/sysctl.conf
        /bin/echo "kernel.shmmax = 2147483648" >> /etc/sysctl.conf 
        /bin/echo "kernel.sem = 250        32000   32    128" >> /etc/sysctl.conf
        /sbin/sysctl -p > /dev/null 2>&1
    fi


    /bin/echo ""
    /bin/echo "* [/etc/services]: configure Informix port"
    read_answer
    if [ "${ANSWER}" = "Y" ]; then
        /bin/echo "informix        ${INFORMIXPORT}/tcp                # Informix" >> /etc/services
    fi
}

#
# Main program: parse command line and execute proper action
#
# Script needs 0 or 1 parameters, otherwise show help & quit
[ "$#" -gt "2" ] && help && exit 1

# Script requires to be run with 'root' credentials
[ ! "`whoami`" = "root" ] && help && echo "FATAL: you must be 'root' to execute this tool." && exit 1

# If number of parameters is correct, parse input
case "$#" in

        0)  FORCE="N"
            os_customize
            os_customize_informix
            create_informix_user
            create_orc_user
            exit 0;;


        1)  case "$1" in         # parse command line for 1 parameter
                  -f)     FORCE="Y"
                          os_customize      
                          os_customize_informix
                          create_informix_user
                          create_orc_user
                          exit 0;;
  
                  -h)     help
        exit 0;;
    esac;;
esac
