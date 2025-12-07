#!/usr/bin/env bash
set -euo pipefail

# --- Color definitions ---
C='\033[0;94m'   # blue (info)
Gr='\033[0;32m'  # green (success)
Ge='\e[33m'      # yellow (warning)
R='\033[91m'     # red (error)
NC='\033[0m'     # reset

CHANNEL="${CHANNEL:-stable}"
COMPOSE_DEST="/usr/local/bin/docker-compose"
COMPOSE_TMP="/tmp/docker-compose.$$"
OVERRIDE_DIR="/etc/systemd/system/docker.service.d"
OVERRIDE_FILE="${OVERRIDE_DIR}/override.conf"
PORTAINER_VOLUME="portainer_data"
PORTAINER_NAME="portainer"
PORTAINER_IMAGE="portainer/portainer-ce"
PORTAINER_PORT_HTTP=9000
PORTAINER_PORT_EDGE=8000

# Determine sudo usage
if [ "$(id -u)" -eq 0 ]; then
  SUDO=""
else
  if command -v sudo >/dev/null 2>&1; then
    SUDO="sudo"
  else
    printf '%b\n' "${R}ERROR: not running as root and sudo not available.${NC}" >&2
    exit 1
  fi
fi

# --- Logging helpers ---
info() { printf '%b\n' "${C}$*${NC}"; }
succ() { printf '%b\n' "${Gr}$*${NC}"; }
warn() { printf '%b\n' "${Ge}$*${NC}"; }
err()  { printf '%b\n' "${R}ERROR: $*${NC}" >&2; }

# --- Docker ---
remove_docker_if_installed() {
  if command -v docker >/dev/null 2>&1 || dpkg -l 2>/dev/null | grep -E 'docker|containerd' >/dev/null 2>&1; then
    warn "Existing Docker installation detected — removing."
    ${SUDO} apt-get update -y
    ${SUDO} apt-get purge -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin || true
    ${SUDO} apt-get autoremove -y || true
    ${SUDO} rm -rf /var/lib/docker /var/lib/containerd || true
    ${SUDO} rm -f /usr/local/bin/docker-compose /usr/bin/docker-compose || true
    succ "Docker removal completed."
  else
    info "No Docker installation found."
  fi
}

install_docker() {
  info "Installing Docker (channel=${CHANNEL})."
  if ! command -v curl >/dev/null 2>&1; then
    warn "curl missing — installing."
    ${SUDO} apt-get update -y
    ${SUDO} apt-get install -y curl ca-certificates gnupg lsb-release
  fi
  ${SUDO} bash -c "CHANNEL=${CHANNEL} && curl -fsSL https://get.docker.com | sh"
  ${SUDO} systemctl enable --now docker
  succ "Docker successfully installed."
}

add_user_to_docker_group() {
  TARGET_USER="${SUDO:+${SUDO_USER:-$USER}}"
  if [ -n "${TARGET_USER}" ]; then
    if getent group docker >/dev/null 2>&1; then
      ${SUDO} usermod -aG docker "${TARGET_USER}" || err "user modification failed"
      succ "User '${TARGET_USER}' added to docker group."
    fi
  fi
}

# --- Docker Compose ---
remove_docker_compose_if_installed() {
  if [ -x "${COMPOSE_DEST}" ]; then
    warn "Existing docker-compose installation detected — removing."
    ${SUDO} rm -f "${COMPOSE_DEST}"
    succ "docker-compose removed."
  else
    info "No Docker Compose installation found."
  fi
}

install_docker_compose() {
  info "Installing Docker Compose."
  LATEST_URL="$(curl -fsSL -o /dev/null -w '%{url_effective}' https://github.com/docker/compose/releases/latest)"
  LATEST_TAG="${LATEST_URL##*/}"
  DOWNLOAD_URL="https://github.com/docker/compose/releases/download/${LATEST_TAG}/docker-compose-$(uname -s)-$(uname -m)"
  curl -fSL "${DOWNLOAD_URL}" -o "${COMPOSE_TMP}"
  ${SUDO} mv "${COMPOSE_TMP}" "${COMPOSE_DEST}"
  ${SUDO} chmod +x "${COMPOSE_DEST}"
  if ${SUDO} "${COMPOSE_DEST}" version >/dev/null 2>&1; then
    succ "Docker Compose installation successful."
  else
    err "Docker Compose installation failed."
    exit 1
  fi
}

# --- Portainer ---
apply_portainer_fix() {
  info "Applying Portainer compatibility fix (API version override)."
  ${SUDO} mkdir -p "${OVERRIDE_DIR}"
  TMP="$(mktemp)"
  cat > "${TMP}" <<'EOF'
[Service]
Environment=DOCKER_MIN_API_VERSION=1.24
EOF
  ${SUDO} mv "${TMP}" "${OVERRIDE_FILE}"
  ${SUDO} chmod 644 "${OVERRIDE_FILE}"
  ${SUDO} systemctl daemon-reload
  ${SUDO} systemctl restart docker
  succ "Portainer compatibility fix applied."
}

install_portainer() {
  # Remove Portainer container, if present
  if ${SUDO} docker ps -a --format '{{.Names}}' | grep -x "${PORTAINER_NAME}" >/dev/null 2>&1; then
    warn "Existing Portainer container found — removing."
    ${SUDO} docker rm -f "${PORTAINER_NAME}" || true
  fi
  # Remove portainer volume if exists. COMMENT THIS OUT IF YOU WANT TO KEEP YOUR DATA
  if ${SUDO} docker volume ls --format '{{.Name}}' | grep -x "${PORTAINER_VOLUME}" >/dev/null 2>&1; then
    ${SUDO} docker volume rm "${PORTAINER_VOLUME}" || true
    succ "Portainer volume '${PORTAINER_VOLUME}' removed."
  fi
  # Deploy Portainer container
  info "Deploying Portainer container."
  ${SUDO} docker volume create "${PORTAINER_VOLUME}" >/dev/null
  ${SUDO} docker run -d \
    -p ${PORTAINER_PORT_EDGE}:8000 -p ${PORTAINER_PORT_HTTP}:9000 \
    --name "${PORTAINER_NAME}" \
    --restart=always \
    -v /var/run/docker.sock:/var/run/docker.sock \
    -v "${PORTAINER_VOLUME}:/data" \
    "${PORTAINER_IMAGE}"
  succ "Portainer deployed on ports ${PORTAINER_PORT_HTTP} and ${PORTAINER_PORT_EDGE}."
}

# --- Open WebUI ---
install_webui() {
  info "Starting Open-WebUI installation."
  if ${SUDO} docker ps -a --format '{{.Names}}' | grep -x "open-webui" >/dev/null 2>&1; then
    warn "Existing open-webui container found — removing."
    ${SUDO} docker rm -f open-webui || true
  fi
  # Remove volumes if present. COMMENT THIS OUT IF YOU WANT TO KEEP YOUR DATA/MODELS
  if ${SUDO} docker volume ls --format '{{.Name}}' | grep -x "ollama" >/dev/null 2>&1; then
    ${SUDO} docker volume rm ollama || true
    succ "Volume 'ollama' removed."
  fi
  if ${SUDO} docker volume ls --format '{{.Name}}' | grep -x "open-webui" >/dev/null 2>&1; then
    ${SUDO} docker volume rm open-webui || true
    succ "Volume 'open-webui' removed."
  fi
  
  info "Creating volumes (ollama, open-webui)."
  ${SUDO} docker volume create ollama >/dev/null || true
  ${SUDO} docker volume create open-webui >/dev/null || true
  info "Deploying Open-WebUI container."
  ${SUDO} docker run -d \
    -p 3000:8080 \
    -v ollama:/root/.ollama \
    -v open-webui:/app/backend/data \
    --name open-webui \
    --restart always \
    ghcr.io/open-webui/open-webui:ollama
  succ "Open-WebUI running on port 3000."
}

# --- Main execution ---
main() {
  info "=== Starting full installation sequence ==="
  
  remove_docker_if_installed
  install_docker
  add_user_to_docker_group
  
  remove_docker_compose_if_installed
  install_docker_compose
  
  apply_portainer_fix
  install_portainer
  
  install_webui

  succ "=== All installations completed successfully. The system will reboot now. ==="

  sleep 2
  sudo reboot
}

main "$@"


