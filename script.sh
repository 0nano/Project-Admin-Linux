#!/bin/bash

if [ ! -d "/home/shared" ] ; then
    mkdir /home/shared/
    chown -R root /home/shared/
    chgrp -R root /home/shared/
    chmod -R a+rwx /home/shared/
    chmod -R o-w /home/shared/
fi

while IFS=";" read -r name surname mail password;
do
    login=$(echo ${name,,} | cut -c1-1)$(echo ${surname,,} | tr -d ' ')
    useradd -m -s /bin/bash "$login"
    echo "$login:${password::-2}" | chpasswd 
    chage -d 0 $login

    if [ ! -d "/home/$login/a_sauver" ] ; then
        mkdir /home/$login/a_sauver/
        chown -R $login /home/$login/a_sauver/
        chgrp -R $login /home/$login/a_sauver/
    fi

    if [ ! -d "/home/shared/$login" ] ; then
        mkdir /home/shared/$login/
        chown -R $login /home/shared/$login/
        chgrp -R $login /home/shared/$login/
        chmod -R a+rwx /home/shared/$login/
        chmod -R go-w /home/shared/$login/
    fi

done < <(tail -n +2 accounts.csv)
