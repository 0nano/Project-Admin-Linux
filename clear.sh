#!/bin/bash

while IFS=";" read -r name surname mail password
do
    login=$(echo ${name,,} | cut -c1-1)$(echo ${surname,,} | tr -d ' ')
    userdel -r $login
done < <(tail -n +2 accounts.csv)

rm -rf /home/shared/

touch clear
crontab clear
rm clear

ssh -i /home/isen/isen mlaure25@10.30.48.100 "cd /home/saves/ && rm -f *.tgz"