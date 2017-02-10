#!/bin/bash

helpmenu()
{
        echo "         -h display helpmenu"
        echo "         Usage: -m | --mysql - install with mysql userparams"
        echo "                -a | --apache add ability to monitor apache"
        echo "                -n | --nginx add ability to monitor nginx"
        echo "                -i | --install - REQUIRED to be a first parameter"
        echo "                -s | --save - generated config will pass to work config. REQUIRED to be a last parameter"
}

Install()
{
		mkdir /root/nxlog_install
		cd /root/nxlog_install
		wget https://nxlog.co/system/files/products/files/1/nxlog-ce_2.9.1716_debian_jessie_amd64.deb 
		dpkg-deb -f nxlog-ce_2.9.1716_debian_jessie_amd64.deb Depends
		dpkg -i nxlog-ce_2.9.1716_debian_jessie_amd64.deb
		apt-get install -fy
		update-rc.d nxlog defaults

		mkdir /etc/nxlog/certs/
		certdir=/etc/nxlog/certs/
		chown nxlog:nxlog /etc/nxlog/certs/
		gpasswd -a nxlog adm
		/etc/init.d/nxlog stop

		#sourceIp=`ifconfig eth0 2>/dev/null|awk '/inet addr:/ {print $2}'|sed 's/addr://'`
		sourceIp=`hostname`
		cd $certdir
		mkdir $certdir/db
		mkdir $certdir/db/certs
		mkdir $certdir/db/newcerts
		touch $certdir/db/index.txt
		echo "01" > $certdir/db/serial
		wget https://raw.githubusercontent.com/imorrt/nxlog/master/ca.crt
		wget https://raw.githubusercontent.com/imorrt/nxlog/master/ca.key
		wget https://raw.githubusercontent.com/imorrt/nxlog/master/ca.config
		openssl req -new -newkey rsa:2048 -nodes -keyout client.key -subj /C=EN/ST=London/L=London/O=$sourceIp/OU=root/CN=$sourceIp/emailAddress=imorrt@gmail.com -out client.csr
		openssl ca -config ca.config -in client.csr -out client.crt -batch
		
		echo -n "Please enter URL for 6000 port, like asd.com:123 : "
		read URL
		echo -n "Please enter URL for 6001 port, like asd.com:123 : "
		read URL2
		
cat << EOF > /root/nxlog_install/nxlog.conf
define ROOT /usr/bin

<Extension json>
    Module      xm_json
</Extension>

<Extension syslog>
    Module      xm_syslog
</Extension>

User nxlog
Group nxlog

Moduledir /usr/lib/nxlog/modules
CacheDir /var/spool/nxlog

define LOGFILE /var/log/nxlog/nxlog.log
LogFile %LOGFILE%
LogLevel INFO

<Extension logrotate>
    Module  xm_fileop
    <Schedule>
        When    @daily
        Exec    file_cycle('%LOGFILE%', 7);
     </Schedule>
</Extension>
EOF

cat << EOF >> /root/nxlog_install/input.conf
<Input in_fromlocal>
        Module im_tcp
        Host 127.0.0.1
        Port 6000
</Input>

<Input in_fromlocal6001>
        Module im_tcp
        Host 127.0.0.1
        Port 6001
</Input>

<Input in_messages>
        Module im_file
        File '/var/log/messages'
        SavePos True
        Exec \$raw_event = substr(\$raw_event, 0, 100000);
        Exec \$FileName = file_name();
</Input>

<Input in_syslog>
        Module im_file
        File '/var/log/syslog'
        SavePos True
        Exec \$raw_event = substr(\$raw_event, 0, 100000);
        Exec \$FileName = file_name();
</Input>
EOF


cat << EOF >> /root/nxlog_install/output.conf
<Output outlocal>
        Module om_http
        Url
        ContentType application/json
        HTTPSCAFile /etc/nxlog/certs/ca.crt
        HTTPSCertFile /etc/nxlog/certs/client.crt
        HTTPSCertKeyFile /etc/nxlog/certs/client.key
        Exec \$Hostname = hostname_fqdn();
        Exec \$source = hostname_fqdn();
</Output>
<Output outlocal6001>
        Module om_http
        YYYY
        ContentType application/json
        HTTPSCAFile /etc/nxlog/certs/ca.crt
        HTTPSCertFile /etc/nxlog/certs/client.crt
        HTTPSCertKeyFile /etc/nxlog/certs/client.key
        Exec \$Hostname = hostname_fqdn();
        Exec \$source = hostname_fqdn();
</Output>
<Output out>
        Module om_http
        Url
        ContentType application/json
        HTTPSCAFile /etc/nxlog/certs/ca.crt
        HTTPSCertFile /etc/nxlog/certs/client.crt
        HTTPSCertKeyFile /etc/nxlog/certs/client.key
        HTTPSAllowUntrusted True
        Exec \$short_message = \$raw_event; # Avoids truncation of the short_message field.
        Exec \$Hostname = hostname_fqdn();
        Exec \$source = hostname_fqdn();
        Exec rename_field("timestamp","@timestamp");to_json();
</Output>
EOF
#sed -i -e "s/\$source=/\$source=\'$sourceIp\'/g" /root/nxlog_install/output.conf
sed -i "s/Url/Url https:\/\/$URL\//g" /root/nxlog_install/output.conf
sed -i "s/YYYY/Url https:\/\/$URL2\//g" /root/nxlog_install/output.conf
cat << EOF >> /root/nxlog_install/route.conf
<Route route-messages>
  Path in_messages => out
</Route>
<Route route-syslog>
  Path in_syslog => out
</Route>
<Route route-fromlocal>
  Path in_fromlocal => outlocal
</Route>
<Route route-fromlocal6001>
  Path in_fromlocal6001 => outlocal6001
</Route>
EOF
}

WithNginx()
{
if ! [ -d /var/log/nginx/ ]; then
mkdir /var/log/nginx/
fi

cat << EOF >> /root/nxlog_install/input.conf
<Input in_nginx>
        Module im_file
        File '/var/log/nginx/*'
        SavePos True
        Exec \$raw_event = substr(\$raw_event, 0, 100000);
        Exec \$FileName = file_name();
</Input>
EOF

cat << EOF >> /root/nxlog_install/route.conf
<Route route-nginx>
  Path in_nginx => out
</Route>
EOF
}



WithApache()
{
if ! [ -d /var/log/apache2/ ]; then
mkdir /var/log/apache2/
chown root:adm /var/log/apache2/
fi
cat << EOF >> /root/nxlog_install/input.conf
<Input in_apache>
        Module im_file
        File '/var/log/apache2/*'
        SavePos True
        Exec \$raw_event = substr(\$raw_event, 0, 100000);
        Exec \$FileName = file_name();
</Input>
EOF

cat << EOF >> /root/nxlog_install/route.conf
<Route route-apache>
  Path in_apache => out
</Route>
EOF
}

WithMysql()
{
if ! [ -d /var/log/mysql/ ]; then
mkdir /var/log/mysql/

grep "mysql:" /etc/passwd >/dev/null
if [ $? -ne 0 ]; then
useradd mysql
fi

chown mysql:adm /var/log/mysql/
fi

cat << EOF >> /root/nxlog_install/input.conf
<Input in_mysql>
        Module im_file
        File '/var/log/mysql/*'
        SavePos True
        Exec \$raw_event = substr(\$raw_event, 0, 100000);
        Exec \$FileName = file_name();
</Input>
EOF

cat << EOF >> /root/nxlog_install/route.conf
<Route route-mysql>
  Path in_mysql => out
</Route>
EOF
}

Save()
{
cat /root/nxlog_install/input.conf >> /root/nxlog_install/nxlog.conf
cat /root/nxlog_install/output.conf >> /root/nxlog_install/nxlog.conf
cat /root/nxlog_install/route.conf >> /root/nxlog_install/nxlog.conf
cat /root/nxlog_install/nxlog.conf > /etc/nxlog/nxlog.conf
/etc/init.d/nxlog start
echo 
echo "COMPLETE"
}

PARSED_OPTIONS=$(getopt -n "$0"  -o hinams --long "help,install,nginx,apache,mysql,save"  -- "$@")
if [ $? -ne 0 ];
then
  exit 1
fi
eval set -- "$PARSED_OPTIONS"
while true;
do
  case "$1" in
 
    -h|--help)
      helpmenu
      shift;;
 
    -m|--mysql)
      WithMysql
      shift;;
 
    -n|--nginx)
      WithNginx
      shift;;
	
    -a|--apache)
      WithApache
      shift;;

    -s|--save)
      Save
      shift;;
	  
    -i|--install)
      Install
	  shift;;
    --)
      shift
      break;;
  esac
done
