#!/bin/bash

while IFS=";" read -r name surname mail password
do
    login=$(echo ${name,,} | cut -c1-1)$(echo ${surname,,} | tr -d ' ')
    userdel -r $login
done < <(tail -n +2 accounts.csv)

rm -rf /home/shared/