# CoBot V2.4

Ce script, découpé en plusieurs fichiers permet d'utiliser un environnement d'inventorisation via un agent GLPI, effacer un/des disques via NWipe, tester les disques durs et la mémoire vive, tout en consignant le résultat des opérations dans un répertoire réseau NFS ou sur un serveur FTP.

Il est étudié pour une installation/utilisation sur une distribution Linux basée sur Debian (testé et utilisé avec Debian-Live 11.7 sans interface graphique).

* ***init.sh***
Permet de récupérer automatiquement la dernière version de l'installateur du script (install.sh) depuis un chemin réseau / adresse web.

* ***main.conf***
Permet de configurer les différentes variables (chemins, options) nécessaires au bon fonctionnement du script.

* ***install.sh***
Permet d'installer l'agent GLPI, installe les paquets nécessaires à l'accès d'un serveur nfs, nwipe et télécharge le script général (script.sh), le script permettant le test des disques durs (smart.sh) ainsi que le logiciel de test de mémoire vive memtester.

* ***inventory.dumb***
Fichier squelette, permettant de surcharger les informations envoyées à GLPI, utilisé afin de déterminer le nom de l'objet inventorié sans avoir à passer par la variable $hostname du système.
  
* ***script.sh***
Permet à l'utilisateur final de saisir un numéro d'inventaire, correspondant ensuite au nom de l'ordinateur dans GLPI, d'éxecuter l'agent-glpi se connectant à un serveur via la fonction AUTH_BASIC d'Apache, monter un dossier partagé avec un serveur NFS afin d'y enregistrer les fichiers logs ou de les envoyer sur un serveur FTP, éxecuter un test de mémoire vive, lancer l'effacement des disques en excluant les périphériques USB, ainsi qu'éxecuter un test rapide, puis long des disques.

* ***smart.sh***
Créé par Meliorator (irc://irc.freenode.net/Meliorator) et amélioré par Ranpha, ce script permet de lister l'ensemble des stockages présents sur la machine et d'effectuer un test SMART short ou long suivant l'option choisie lors de son appel.

Merci à M3GHAN et Doxah pour leurs contributions et tests.
