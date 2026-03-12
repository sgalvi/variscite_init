eseguire gli script in questa sequenza
cleanup.sh
init.sh
setup.sh



rinominare il file user_config.conf_template in user_config.conf e aggiungere la password hashata.
Per hashare la password eseguire il comando `openssl passwd -6 "tuapassword"`. incollarla quindi nel campo password di user_config.conf

