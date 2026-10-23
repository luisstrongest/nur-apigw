#!/bin/bash
# =============================================================================
# Inicializacion de Keycloak (se ejecuta en el contenedor "keycloak-init")
#
# Crea, si no existen:
#   1. El realm de la aplicacion
#   2. El client confidencial "api-gateway" con Direct Access Grants
#      (necesario para que POST /api/login canjee usuario/contrasena por token)
#   3. Los usuarios del equipo, todos con la misma contrasena generica
#
# Es idempotente: se puede correr N veces; lo que ya existe se omite. Como
# Keycloak persiste en PostgreSQL, en los arranques siguientes no crea nada.
# =============================================================================
set -euo pipefail

KCADM=/opt/keycloak/bin/kcadm.sh
SERVER="${KEYCLOAK_INTERNAL_URL:-http://keycloak:8080}"
REALM="${KEYCLOAK_REALM:-nur}"
CLIENT_ID="${KEYCLOAK_CLIENT_ID:-api-gateway}"
CLIENT_SECRET="${KEYCLOAK_CLIENT_SECRET:?Falta KEYCLOAK_CLIENT_SECRET}"
USERS_PASSWORD="${USERS_PASSWORD:-Admin789456*}"
# kcadm guarda su sesion en $HOME; en el contenedor no hay HOME escribible
export HOME=/tmp

# username|nombre|apellido
USERS=(
  "lhurtado|Luis|Hurtado"
  "grobles|G|Robles"
  "amolina|Alvaro|Molina"
  "ccuelar|Carlos|Cuellar"
  "aavila|A|Avila"
)

echo ">> Autenticando contra ${SERVER} como ${KC_BOOTSTRAP_ADMIN_USERNAME}..."
for i in {1..30}; do
  if "$KCADM" config credentials --server "$SERVER" --realm master \
      --user "$KC_BOOTSTRAP_ADMIN_USERNAME" --password "$KC_BOOTSTRAP_ADMIN_PASSWORD" >/dev/null 2>&1; then
    break
  fi
  [ "$i" -eq 30 ] && { echo "!! No se pudo autenticar en Keycloak"; exit 1; }
  sleep 3
done

# --- 1. Realm ----------------------------------------------------------------
if "$KCADM" get "realms/${REALM}" >/dev/null 2>&1; then
  echo "-- Realm '${REALM}' ya existe"
else
  "$KCADM" create realms \
    -s realm="$REALM" \
    -s enabled=true \
    -s sslRequired=none \
    -s accessTokenLifespan=1800
  echo "++ Realm '${REALM}' creado (tokens validos por 30 min)"
fi

# --- 2. Client del gateway -----------------------------------------------------
CID=$("$KCADM" get clients -r "$REALM" -q clientId="$CLIENT_ID" --fields id --format csv --noquotes)
if [ -n "$CID" ]; then
  echo "-- Client '${CLIENT_ID}' ya existe"
else
  "$KCADM" create clients -r "$REALM" \
    -s clientId="$CLIENT_ID" \
    -s enabled=true \
    -s protocol=openid-connect \
    -s publicClient=false \
    -s clientAuthenticatorType=client-secret \
    -s secret="$CLIENT_SECRET" \
    -s directAccessGrantsEnabled=true \
    -s standardFlowEnabled=false \
    -s serviceAccountsEnabled=false
  echo "++ Client '${CLIENT_ID}' creado"
fi

# --- 3. Usuarios -------------------------------------------------------------
for entry in "${USERS[@]}"; do
  IFS='|' read -r username first last <<< "$entry"

  UID_=$("$KCADM" get users -r "$REALM" -q username="$username" -q exact=true --fields id --format csv --noquotes)
  if [ -n "$UID_" ]; then
    echo "-- Usuario '${username}' ya existe"
    continue
  fi

  # Nombre, apellido y email verificado son obligatorios en el perfil de
  # usuario de Keycloak 24+; sin ellos el login falla con
  # "Account is not fully set up".
  "$KCADM" create users -r "$REALM" \
    -s username="$username" \
    -s enabled=true \
    -s firstName="$first" \
    -s lastName="$last" \
    -s email="${username}@nur.edu.bo" \
    -s emailVerified=true

  "$KCADM" set-password -r "$REALM" --username "$username" --new-password "$USERS_PASSWORD"
  echo "++ Usuario '${username}' creado"
done

echo ">> Keycloak inicializado"
