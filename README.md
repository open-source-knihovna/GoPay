![logo KohaCZ](https://github.com/open-source-knihovna/SmartWithdrawals/blob/master/SmartWithdrawals/koha_cz.png "Logo Česká komunita Koha")
![logo R-Bit Technology, s.r.o.](https://github.com/open-source-knihovna/SmartWithdrawals/blob/master/SmartWithdrawals/logo.png "Logo R-Bit Technology, s.r.o.")
![logo MK ČR](https://github.com/open-source-knihovna/SmartWithdrawals/blob/master/SmartWithdrawals/logo_mkcr.png "Logo MK ČR")

Zásuvný modul vytvořila společnost R-Bit Technology, s. r. o. ve spolupráci s českou komunitou Koha, za finančního přispění Ministerstva kultury České republiky.

# Úvod

Zásuvný modul 'GoPay' implementuje možnost platit uživatelům knihovny poplatky on-line přes českou platební bránu GoPay. Platba může být iniciována jak z OPACu Kohy, tak i z téměř libovolného jiné systému (VuFind, Centrální portál knihove atp.). Pokud je platba úspěšná dojde k okamžité úhradě všech dlužných poplatků v systému. Součástí modulu je jednoduchá konfigurace, kde se vyplňují identifikační údaje pro bránu.

# Instalace

## Zprovoznění Zásuvných modulů

Institut zásuvných modulů umožňuje rozšiřovat vlastnosti knihovního systému Koha dle specifických požadavků konkrétní knihovny. Zásuvný modul se instaluje prostřednictvím balíčku KPZ (Koha Plugin Zip), který obsahuje všechny potřebné soubory pro správné fungování modulu.

**POZOR: Pokud nepoužíváte instalační balíčky KohaCZ budete muse na svůj server vložit soubor, který umožní propojit Kohu a zásuvný modul. Jde o pay_api.zip a stáhnout jej můžete ze stejného místa jako samotný modul. Archiv rozzipujte a obsažený soubor zkopíujte do adresáře .../koha/svc/. Vlastníka (příkaz chown) a práva k souboru (příkaz chmod) definujte stejně, jako mají ostatní soubory v tomto adresáři. Tato procedura se vás netýká, pokud používáte balíček KohaCZ.**

Pro využití zásuvných modulů je nutné, aby správce systému tuto možnost povolil v nastavení.

Nejprve je zapotřebí provést několik změn ve vaší instalaci Kohy:

* V souboru koha-conf.xml změňte `<enable_plugins>0</enable_plugins>` na `<enable_plugins>1</enable_plugins>`
* Ověřte, že cesta k souborům ve složce `<pluginsdir>` existuje, je správná a že do této složky může webserver zapisovat
* Pokud je hodnota `<pluginsdir>` např. `/var/lib/koha/kohadev/plugins`, vložte následující kód do konfigurace webserveru:
```
Alias /plugin/ "/var/lib/koha/kohadev/plugins/"
<Directory "/var/lib/koha/kohadev/plugins">
  Options +Indexes +FollowSymLinks
  AllowOverride All
  Require all granted
</Directory>
```
* Načtěte aktuální konfiguraci webserveru příkazem `sudo service apache2 reload`

Jakmile je nastavení připraveno, budete potřebovat změnit systémovou konfigurační hodnotu UseKohaPlugins v administraci Kohy. Aktuální verzi modulu [stahujte v sekci Releases](https://github.com/open-source-knihovna/GoPay/releases).

## Nastavení specifické pro modul



Více informací, jak s nástrojem pracovat naleznete na [wiki](https://github.com/open-source-knihovna/GoPay/wiki)
