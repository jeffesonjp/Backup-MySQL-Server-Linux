# Backup-MySQL-Server-Linux

Projeto para backups regulares de bancos de dados MySQL Server e envio para conta em nuvem com acompanhamento via log

## Instruções
A estrutura de diretório do projeto é a seguinte
```sh
└───MySQLServer
     │  bkpmysql.sh
     │  rclone
     │  rclone.conf
     ├──backups
     └──logs
```
Baixe o [rclone](https://downloads.rclone.org/current/rclone-current-linux-amd64.zip), descompacte e adicione o binário ao diretório

Configure um remoto para o rclone e edite no bkpmysql.sh em RCLONE_DEST. Não será abordada essa parte de criação de remotopara o rclone pois não é o foco
Em HOST_PROFILES, coloque os nomes de perfis dos bancos de dados. A seguir crie os perfis usando o comando
```sh
mysql_config_editor set --login-path=perfil1 --host=IP --user=root --password
```
Escolha um nome para o perfil, o IP do servidor do banco de dados e o usuário. A seguir, será solcitada a senha do usuário que tem acesso a esse banco de dados.
Sugestão: coloque os perfis na mesma ordem da variável.

Edite as variáveis a serem usadas para o envio de logs em sendEmail no final do script.

Para garantir o funcionamento do script, instale os pacotes necessários:
```sh
apt-get install -y mysql-client-8.0 p7zip-full sendemail libnet-ssleay-perl libio-socket-ssl-perl
```

Dê as permissões aos executáveis bkpmysql.sh e rclone com:
```sh
chmod +x bkpmysql.sh rclone
```

Configure um agendamento no cron, conforme sua necessidade.
