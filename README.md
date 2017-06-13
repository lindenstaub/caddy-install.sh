# caddy-install.sh

Quick hack of the script at [](https://getcaddy.com/) ([github](https://github.com/caddyserver/getcaddy.com)) to work with systemd and make the folders/files expected by caddy

!!! This script will probably break on any system without systemd. !!!

Make a pull request if you have a patch to make it init system agnostic.


### TROUBLESHOOTING
Error: caddy.service start request repeated too quickly, refusing to start.

Comment out this line in the /etc/systemctl/system/caddy.service file to see an actual error:

`Restart=on-failure`


Then you have to make systemctl see that the file is changed:

```
systemctl daemon-reload
systemctl start caddy
systemctl status caddy
```

Or to manually start caddy and see it's output directly:

```
sudo -u www-data -h /usr/local/bin/caddy -log stdout -agree=true -conf=/etc/caddy/Caddyfile -root=/var/tmp
```

