# Publicación en Lepton

La web pública, el manifiesto y la imagen se sirven desde:

```text
/Users/Shared/srv/http/mantilla.ca/cdmx-radxa-flash
```

1. Copie `site/` a ese directorio y la imagen más su archivo `.sha512` a
   `downloads/`.
2. Añada `Caddyfile.snippet` al servidor Caddy que escucha en
   `127.0.0.1:18080`, valide con `caddy validate` y recargue Caddy.
3. Cree un túnel dedicado con `cloudflared tunnel create cdmx-radxa-flash` y
   copie `cloudflared.yml.example`, sustituyendo `TUNNEL_ID` y `USERNAME`.
4. Enrute el nombre con
   `cloudflared tunnel route dns --overwrite-dns cdmx-radxa-flash cdmx-radxaflash.mantilla.ca`.
5. Ejecute el túnel como servicio de usuario para que vuelva después de cada
   reinicio.

No guarde en Git el JSON de credenciales ni un token del túnel. Antes de
publicar, compruebe la imagen en Lepton con `shasum -a 512 -c` y pruebe la web,
el manifiesto y una descarga parcial desde Internet.
