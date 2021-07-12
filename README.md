# Развертывание
**Для развертывания использовать только операционную систему CentOS 7. С другими дистрибутивами и версиями скрипт несовместим.**

```bash
sudo yum install epel-release git firewalld
sudo systemctl enable firewalld
sudo systemctl start firewalld
sudo yum update
sudo reboot

# Создание пользователя
sudo adduser ovpn
sudo passwd ovpn
sudo usermod -aG wheel ovpn

# После перезагрузки
git clone https://github.com/4b4d86b2/vpnmgr.git
cd vpnmgr
chmod +x deploy_vpnmgr.sh
sudo ./deploy_vpnmgr.sh
```
В самом начале скрипт попросит вас ввести некоторые переменные, которые он будет использовать для установки. Чтобы оставить значение по умолчанию, просто нажмите Enter. Но: проверьте свой внешний IP-адрес. Если он не соответствует тому, что вам дал ваш провайдер, измените его на правильный. Кроме того, если ваш провайдер использует собственный брандмауэр (например, AWS), вы также должны открыть порт OpenVPN в этом брандмауэре (вы можете увидеть выбранный порт OpenVPN в начале скрипта, кроме того, вы можете изменить его на другой). Для этой сборки вы должны открыть порт UDP, а не TCP.

# Использование vpnmgr
```text
Использование: vpnmgr команда [опции]
   Управление пользовательскими конфигурациями OpenVPN
   
   Команда:
       create       Создание пользовательской конфигурации
       delete       Удаление пользовательской конфигурации
       help         Вывести справку
       status       Показать иформацию по всем пользовательким конфигурациям
       update       Обновление утилиты vpmgr
       version      Показать версию vpnmgr
   
   Примеры:
       vpnmgr (create|delete) name - Создание/удаление пользовательской конфигурации. В качестве опции используется имя
       vpnmgr status [name] - Показать иформацию по пользовательким конфигурациям. Также можно ввести имя конкретной конфигурации и увидеть более подробную информацию о ней.
```

Например, чтобы создать пользовательскую конфигурацию, выполните `sudo vpnmgr create Name`
> Используйте `sudo` с vpnmgr, так как утилите нужны права суперпользователя: `sudo vpnmgr ...`

# Как скачивать пользовательские конфигурации
Для этого вы можете использовать sftp. Для скачивания пользовательской конфигурации с именем User_config, выполните:
```
sftp user@SERVER-IP
> get /etc/openvpn/vpnmgr/server/client_configs/User_config.ovpn
```

