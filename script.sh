#!/bin/bash

echo "Avant de démarrer la création des comptes, veuillez reseigner l'identifiant pour la connexion SSH ainsi que la clé à utiliser."
read -p "Entrez l'IP du serveur : " sship
read -p "Entrez l'identifiant : " sshlogin
read -p "Entrez la clef ssh à utiliser (mettez l'adresse depuis le dossier racine) : " sshkey
echo

echo "Avant de démarrer la création des comptes, veuillez entrer les informations pour l'envoi du mail."
read -p "Entrez l'adresse du serveur SMTP : " adresse
read -p "Entrez le login du compte : " superlogin
read -sp "Entrez le mot de passe du compte : " superpassword
echo

superpassword=${superpassword/@/%40}
superpassword=${superpassword/\!/\\\!}

# Création du dossier shared appartenant à root,
# avant la création, on vérifie qu'il n'existe pas
if [ ! -d "/home/shared" ] ; then
    mkdir /home/shared/
    chown -R root /home/shared/
    chgrp -R root /home/shared/
    chmod -R a+rwx /home/shared/
    chmod -R o-w /home/shared/
fi

# Création du dossier saves s'il n'existe pas déjà sur le serveur distant
ssh -i $sshkey $sshlogin@$sship "mkdir -p /home/saves"

# Mise en place de Nextcloud
# Utilisation d'un deb pour l'installation de nextcloud
# https://git.jurisic.org/ijurisic/nextcloud-deb
ssh -n -i $sshkey $sshlogin@$sship "wget -qO - https://apt.jurisic.org/Release.key | gpg --dearmor | sudo dd of=/usr/share/keyrings/jurisic-keyring.gpg"
ssh -n -i $sshkey $sshlogin@$sship "echo \"deb [ signed-by=/usr/share/keyrings/jurisic-keyring.gpg ] https://apt.jurisic.org/debian/ $(lsb_release -cs) main contrib non-free\" | tee /etc/apt/sources.list.d/jurisic.list"
ssh -n -i $sshkey $sshlogin@$sship "apt update"
ssh -n -i $sshkey $sshlogin@$sship "apt install nextcloud-server"

# On installe nextcloud avec les paramètres suivants :
# - le login et le mot de passe de l'administrateur
ssh -n -i $sshkey $sshlogin@$sship "/usr/sbin/occ maintenance:install --admin-user=\"nextcloud-admin\" --admin-pass=\"N3x+_Cl0uD\""

# Lecture du fichier csv avec les informations nécessaires
# à la création du compte, on n'interprète pas les \n avec le flag -r
# On passe la première ligne d'information
while IFS=";" read -r name surname mail password;
do
    # On créé le login de chaque utilisateur en prenant la première lettre du prénom
    # et le nom de famille, le login est mis en minuscule 
    # et on supprime les espaces des noms composés
    login=$(echo ${name,,} | cut -c1-1)$(echo ${surname,,} | tr -d ' ')
    
    # On redéfinie le password afin de supprimer le caractère \r qui n'est pas compris par Linux
    # et qui peut apparaître si le ficher a été écrit sur un Windows
    # la solution a été trouvé à l'aide de la question stackoverflow suivante :
    # https://stackoverflow.com/questions/800030/remove-carriage-return-in-unix#800644
    password=$(echo $password | sed 's/\r$//' | sed 's/ $//')
    
    # On créé l'utilisateur avec le login et le mot de passe créé plutôt
    # On défini qu'à la première connexion le mot de passe doit être changé
    useradd -m -s /bin/bash "$login"
    echo "$login:$password" | chpasswd 
    chage -d 0 $login

    # On créé pour chaque utilisateur le dossier a_sauver
    # pour la sauvegarde automatique des données
    if [ ! -d "/home/$login/a_sauver" ] ; then
        mkdir /home/$login/a_sauver/
        chown -R $login /home/$login/a_sauver/
        chgrp -R $login /home/$login/a_sauver/
    fi

    # On créé pour chaque utilisateur leur dossier
    # dans le dossier shared
    if [ ! -d "/home/shared/$login" ] ; then
        mkdir /home/shared/$login/
        chown -R $login /home/shared/$login/
        chgrp -R $login /home/shared/$login/
        chmod -R a+rwx /home/shared/$login/
        chmod -R go-w /home/shared/$login/
    fi

    # On envoi le mail avec les informations de connexion pour l'utilisateur :
    # - login
    # - mot de passe
    # - Information de réinitialisation du mot de passe
    ssh -n -i $sshkey $sshlogin@$sship "mail --subject \"Information de connexion\" --exec \"set sendmail=smtp://$(echo ${superlogin/@/%40}):$superpassword@$adresse:587\" --append \"From:$superlogin\" maxence.laurent@isen-ouest.yncrea.fr <<< $(echo -e \"Bonjour, Vous avez recu ce mail pour vous donner les informations de connexion a votre session. Je vous informe que le mot de passe qui vous est fourni ici devra etre change a la premiere connexion en cas de perte, veuillez contacter l administrateur. login = $login \| Mot de passe = $password \| Cordialement, L administrateur\")"
    
    # On active la sauvegarde du dossir a_sauver pour chaque utilisateur
    # https://stackoverflow.com/questions/878600/how-to-create-a-cron-job-using-bash-automatically-without-the-interactive-editor
    crontab -l > newcron
    echo "*/2 * * * 1-5 tar czvf /home/$login/save_$login.tgz -C \"/home/$login\" a_sauver/ && chmod a+x /home/$login/save_$login.tgz && scp -i $sshkey /home/$login/save_$login.tgz $sshlogin@$sship:/home/saves/ && rm /home/$login/save_$login.tgz" >> newcron
    crontab newcron
    rm newcron

    # On créé le script de restauration de la sauvegarde
    echo "scp -i $sshkey $sshlogin@$sship:/home/saves/save_$login.tgz /home/$login && rm -rf /home/$login/a_sauver/ && tar xzvf /home/$login/save_$login.tgz -C \"/home/$login\" a_sauver/ && rm -rf /home/$login/save_$login.tgz" > /home/$login/retablir_sauvegarde.sh
    chmod a+x /home/$login/retablir_sauvegarde.sh

    # On ajoute l'utilisateur à nextcloud
    # On considère que l'utilisateur se connecte en root
    ssh -n -i $sshkey $sshlogin@$sship "export OC_PASS=\"$password\" && /usr/sbin/occ user:add --password-from-env --display-name=\"$name $surname\" --group=\"users\" \"$login\""

    # On créé le tunneling pour ouvrir nextcloud sur l'ordinateur
    # de l'utilisateur
    echo "ssh -L 4242:$sship:80 -NT $sshlogin@$sship" > /home/$login/tunnel_nextcloud.sh
    chown root:root /home/$login/tunnel_nextcloud.sh
    chmod 771 /home/$login/tunnel_nextcloud.sh

done < <(tail -n +2 accounts.csv)

# Installation d'éclipe sans l'utilisation de apt
wget --directory-prefix=/opt/ https://ftp.fau.de/eclipse/technology/epp/downloads/release/2023-03/R/eclipse-java-2023-03-R-linux-gtk-x86_64.tar.gz && tar xzvf /opt/eclipse-java-2023-03-R-linux-gtk-x86_64.tar.gz -C "/opt/" eclipse && chown -R root:root /opt/eclipse/ && ln -s /opt/eclipse/eclipse /usr/local/bin/eclipse && rm -f /opt/eclipse-java-2023-03-R-linux-gtk-x86_64.tar.gz

# Blocage des connexions FTP entrantes et sortantes
iptables -A OUTPUT -p tcp --dport 21 -j DROP
iptables -A INPUT -p tcp --dport 21 -j DROP

# Blocage des connexions UDP entrantes et sortantes
iptables -A INPUT -p udp -j DROP
iptables -A OUTPUT -p udp -j DROP

# On installe htop pour visualiser l´utilisation du serveur
ssh -n -i $sshkey $sshlogin@$sship "apt install htop"

# On crée le ficher pour ouvrir le htop a distance
echo "ssh -i $sshkey $sshlogin@$sship \"htop\"" > /home/tunnel_htop.sh
chown root:root /home/tunnel_htop.sh
chmod 771 /home/tunnel_htop.sh
