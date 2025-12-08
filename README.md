## **Zielgruppen:**

Dieses Skript setzt im wesentlichen folgende Befehle um (bzw. ist auf gewisse Weise mit ihnen idempotent):

```bash 
# DOCKER DEINSTALLIEREN:
sudo apt purge -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo apt autoremove -y
sudo rm -rf /var/lib/docker
sudo rm -rf /var/lib/containerd


# DOCKER INSTALLIEREN:
curl -sSL https://get.docker.com/ | CHANNEL=stable sh
sudo usermod -aG docker $USER
sudo systemctl enable --now docker


# DOCKER COMPOSE INSTALLIEREN (optional):
sudo su

LATEST=$(curl -Ls -w %{url_effective} -o /dev/null https://github.com/docker/compose/releases/latest) && LATEST=${LATEST##*/} && curl -L https://github.com/docker/compose/releases/download/$LATEST/docker-compose-$(uname -s)-$(uname -m) > /usr/local/bin/docker-compose

exit

sudo chmod +x /usr/local/bin/docker-compose


# FIX FÜR PORTAINER UNTER DOCKER 29:
sudo systemctl edit docker.service

#  Add this part above the line _### Lines below this comment will be discarded:_
#  [Service]
#  Environment=DOCKER_MIN_API_VERSION=1.24

# Save the file and exit

sudo systemctl restart docker


# PORTAINER INSTALLIEREN:
sudo docker volume create portainer_data

sudo docker run -d \
  -p 8000:8000 \
  -p 9000:9000 \
  --name=portainer \
  --restart=always \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v portainer_data:/data \
  portainer/portainer-ce


# Open WebUI INSTALLIEREN:
sudo docker rm -f open-webui
sudo docker volume create ollama
sudo docker volume create open-webui

sudo docker run -d \
  -p 3000:8080 \
  -v ollama:/root/.ollama \
  -v open-webui:/app/backend/data \
  --name open-webui \
  --restart always \
  ghcr.io/open-webui/open-webui:ollama

sudo reboot
```
Genauer aufgedröselt, sieht das so aus:
```bash
# DOCKER DEINSTALLIEREN:
# Vorhandene Docker-Installation entfernen (falls vorhanden)
sudo apt-get update -y
sudo apt-get purge -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin || true
sudo apt-get autoremove -y || true
sudo rm -rf /var/lib/docker /var/lib/containerd || true
sudo rm -f /usr/local/bin/docker-compose /usr/bin/docker-compose || true


# DOCKER INSTALLIEREN:
# Falls curl fehlt, wird es installiert
sudo apt-get update -y
sudo apt-get install -y curl ca-certificates gnupg lsb-release

# Docker über das offizielle Install-Skript installieren (setzt CHANNEL=stable)
CHANNEL=stable
sudo bash -c "CHANNEL=${CHANNEL} && curl -fsSL https://get.docker.com | sh"

# Docker aktivieren und starten
sudo systemctl enable --now docker

# Benutzer zur Docker-Gruppe hinzufügen (falls nötig)
# Ersetze <username> durch den korrekten Benutzer
sudo usermod -aG docker <username>


# DOCKER COMPOSE INSTALLIEREN (optional):
# Vorhandenes docker-compose entfernen (falls vorhanden)
sudo rm -f /usr/local/bin/docker-compose

# docker-compose installieren (neuste Release wird automatisch geholt)
# Neueste Release-URL und Tag bestimmen
LATEST_URL="$(curl -fsSL -o /dev/null -w '%{url_effective}' https://github.com/docker/compose/releases/latest)"
LATEST_TAG="${LATEST_URL##*/}"
DOWNLOAD_URL="https://github.com/docker/compose/releases/download/${LATEST_TAG}/docker-compose-$(uname -s)-$(uname -m)"

# Herunterladen in eine temporäre Datei (COMPOSE_TMP)
curl -fSL "${DOWNLOAD_URL}" -o /tmp/docker-compose.$$

# Datei verschieben und ausführbar machen
sudo mv /tmp/docker-compose.$$ /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose

# Installation prüfen
sudo /usr/local/bin/docker-compose version


# FIX FÜR PORTAINER UNTER DOCKER 29:
# Portainer-Kompatibilitätsfix anwenden (systemd-Override erstellen)
# Override-Verzeichnis erstellen
sudo mkdir -p /etc/systemd/system/docker.service.d

# Temporäre Datei erstellen und Inhalt einfügen
TMP="$(mktemp)"
cat > "${TMP}" <<'EOF'
[Service]
Environment=DOCKER_MIN_API_VERSION=1.24
EOF

# Override-Datei verschieben, Rechte setzen, systemd neu laden und Docker neustarten
sudo mv "${TMP}" /etc/systemd/system/docker.service.d/override.conf
sudo chmod 644 /etc/systemd/system/docker.service.d/override.conf
sudo systemctl daemon-reload
sudo systemctl restart docker


# PORTAINER INSTALLIEREN:
# Portainer-Volume erstellen
sudo docker volume create portainer_data >/dev/null

# Vorhandenen Portainer-Container entfernen (falls vorhanden)
sudo docker rm -f portainer || true

# Portainer-Container starten
sudo docker run -d \
  -p 8000:8000 -p 9000:9000 \
  --name "portainer" \
  --restart=always \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v "portainer_data:/data" \
  "portainer/portainer-ce"


# Open WebUI INSTALLIEREN:
# Vorhandenen open-webui-Container entfernen (falls vorhanden)
sudo docker rm -f open-webui || true

# Notwendige Volumes erstellen
sudo docker volume create ollama >/dev/null || true
sudo docker volume create open-webui >/dev/null || true

# Open WebUI-Container starten
sudo docker run -d \
  -p 3000:8080 \
  -v ollama:/root/.ollama \
  -v open-webui:/app/backend/data \
  --name open-webui \
  --restart always \
  ghcr.io/open-webui/open-webui:ollama

# Abschließender Neustart
sudo reboot
```

WARNUNG:
Wer einfach nur das Skript durchlaufen lässt, versteht nicht, wie es funktioniert. Deshalb sollte die Erstinstallation auf jeden Fall händisch ausgeführt werden, indem die genannten Befehle einer nach dem anderen (in der kurzen Variante oder der längeren) ins Terminal eingegeben werden, sodass man sieht, was im einzelnen passiert. Wer aber dann tiefer in das Arbeiten mit Open WebUI eingestiegen ist und sich nicht mehr mit händischen Neuinstallationen aufhalten will, für den ist das Skript ein gute Hilfe. 

Zweitens ist das Skript auch für alle, die bei der händischen Installation gescheitert sind. 

Und drittens könnte es für den einen oder anderen interessant sein, zu sehen, wie die oben aufgeführten Befehle in ein Bash-Skript gepackt werden können, wie also Bash Imperative durch Prozeduren (Funktionen) kontrolliert und gesteuert werden können.

## **Systemvoraussetzungen**

Ich habe das Skript bislang getestet unter: 

* Debian 13.2
* Ubuntu-Server 24.0.3
* Mint 21.3, 22.1 und 22.2 

Damit sollte es auch auf Ubuntu-Derivaten, wie Linux Lite oder PopOS laufen, sowie auf Debian-Derivaten, wie ParrotOS, Kali usw. ausführbar sein. Speziell Debian 13 muss allerdings erstmal folgendermaßen dazu bereit gemacht werden:
 
1. In ```/etc/apt/sources.list``` die Zeile
```bash
deb cdrom:[Debian GNU/Linux 13.1.0 _Trixie_ - Official amd64 DVD Binary-1 with firmware 20250906-10:24]/ trixie contrib main non-free-firmware
```
auskommentieren, also:
```
#deb cdrom:[Debian GNU/Linux 13.1.0 _Trixie_ - Official amd64 DVD Binary-1 with firmware 20250906-10:24]/ trixie contrib main non-free-firmware
```

2. als ```root``` einloggen und sudo installieren:
```bash
apt-get update
apt install -y sudo
```

3. User zur Gruppe sudo hinzufügen:
```bash
usermod -aG sudo <username> 
```
Ich vermute, dass das Skript ohne irgendwelche Anpassungen auf allen debian-basierten Systemen funktionieren wird.

## **Quickstart**

1\) Kopiere die Datei  ```setup.sh```ins Home-Verzeichnis des Servers, z.B:

```bash
scp setup.sh <username>@<server-ip>:/home/<username>
```

2\) Mache die Datei auf dem Server ausführbar:

```bash
sudo chmod +x setup.sh
```

3\) Starte das Skript auf dem Server:

```bash
./setup.sh
```
Portainer ist nun im Browser aufrufbar unter **\<server-ip\>:9000**. Dort muss auch _umgehend_ ein Useraccount angelegt werden. Und Open WebUI ist aufrufbar unter **\<server-ip\>:3000**. Der allererste Start des open-webui Containers kann einige Minuten dauern. Bei jedem weiteren Reboot oder Neustart soll der open-webui Container dann aber immer zügig auf ```healthy```springen.

Das Skript bindet keine GPU ein. Wer das haben möchte, fügt im ```setup.sh``` im Block der Zeilen 148-156 folgendermaßen ```--gpus all``` ein:
```bash
${SUDO} docker run -d \
    -p 3000:8080 \
    -v ollama:/root/.ollama \
    -v open-webui:/app/backend/data \
    --gpus all \
    --name open-webui \
    --restart always \
    ghcr.io/open-webui/open-webui:ollama
succ "Open-WebUI running on port 3000 with GPU support."
```

## **Troubleshooting**

Augrund des Fixes ist Portainer nur ```running```, aber nicht ```healthy```. Das funktioniert aber genauso gut und geht im Moment nicht besser. Wer es ```healthy``` haben will, muss Docker 28 verwenden (und den Fix auskommentieren).

Beim allerersten Start muss der open-webui Container manchmal nochmal restartet werden oder sogar noch ein Reboot gemacht werden, damit er auf ```healthy``` springt. Die Ladehemmungen des Open WebUI Containers treten nur dann auf, wenn auch ein neues Image gezogen wird, also wenn man Docker neuinstalliert hat. Wenn bereits ein Image vorhanden ist, springt der Container zügig auf ```healthy```.
