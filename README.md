# nur-apigw · API Gateway con Spring Cloud Gateway + Keycloak

API Gateway desarrollado para el Diplomado NUR. Enruta las peticiones hacia
[JSONPlaceholder](https://jsonplaceholder.typicode.com) y protege las rutas con
**Bearer tokens (JWT)** emitidos por **Keycloak**, que guarda sus datos en
**PostgreSQL**.

## 1. Endpoints

| Endpoint de entrada | ¿Requiere Bearer token? | Acción                                                                        |
| :------------------ | :---------------------: | :---------------------------------------------------------------------------- |
| `POST /api/login`   | No                      | Genera un Bearer token a partir de las credenciales enviadas en el body        |
| `GET /api/users`    | Sí                      | Enruta a `https://jsonplaceholder.typicode.com/users`                          |
| `GET /api/posts`    | Sí                      | Enruta a `https://jsonplaceholder.typicode.com/posts`                          |

> **Nota sobre "redirección":** el gateway funciona como *proxy inverso*. No
> responde con un HTTP 302: reenvía la petición al destino y devuelve su
> respuesta. Así el cliente nunca llama directo al servicio interno y el token
> sí protege algo. También se enrutan las sub-rutas (`/api/users/3`,
> `/api/posts/1`). La cabecera `Authorization` se quita antes de reenviar, para
> no pasar el token a un servicio de terceros.

## 2. Arquitectura

```
                       ┌──────────────────────────── red docker: apigw-net ─────────────────────────┐
                       │                                                                            │
 Cliente ──► :8090 ──► │  api-gateway (Spring Cloud Gateway)                                        │
                       │    ├─ POST /api/login ──► keycloak:8080  /realms/nur/.../token (password)  │
                       │    ├─ valida JWT con  ──► keycloak:8080  /realms/nur/.../certs (JWKS)      │
                       │    ├─ GET /api/users  ──► https://jsonplaceholder.typicode.com/users ──────┼──► Internet
                       │    └─ GET /api/posts  ──► https://jsonplaceholder.typicode.com/posts ──────┼──► Internet
                       │                                                                            │
         :8180 ──────► │  keycloak  ──►  keycloak-db (PostgreSQL 16, volumen keycloak-db-data)     │
                       │  keycloak-init (kcadm.sh: crea realm, client y usuarios; luego termina)   │
                       └────────────────────────────────────────────────────────────────────────────┘
```

| Servicio        | Imagen                              | Función                                                  |
| :-------------- | :---------------------------------- | :------------------------------------------------------- |
| `api-gateway`   | `luisstrongest/nur-apigw:1.0.0`     | Spring Boot 3.5 + Spring Cloud Gateway 2025.0 (Java 21)  |
| `keycloak`      | `quay.io/keycloak/keycloak:26.4`    | Identity Provider: emite y firma los JWT                 |
| `keycloak-db`   | `postgres:16-alpine`                | Persistencia de Keycloak                                 |
| `keycloak-init` | `quay.io/keycloak/keycloak:26.4`    | Ejecuta [`keycloak/init-keycloak.sh`](keycloak/init-keycloak.sh) |

Orden de arranque (con `depends_on` y healthchecks):
`keycloak-db` (healthy) → `keycloak` (healthy) → `keycloak-init` (completed) → `api-gateway`.

## 3. Ejecución

Requisitos: Docker Engine 24 o superior y Docker Compose V2.

```bash
git clone https://github.com/luisstrongest/nur-apigw.git
cd nur-apigw

cp .env.example .env     # luego edita las contraseñas marcadas "cambiar-por-..."
docker compose up -d --build
docker compose ps
```

> El **primer arranque tarda varios minutos**: Keycloak compila su
> configuración (Quarkus) y crea el esquema de base de datos. Para seguir el
> avance: `docker compose logs -f keycloak keycloak-init`. El gateway arranca
> cuando `keycloak-init` termina con `>> Keycloak inicializado`.

| URL                         | Descripción                                       |
| :-------------------------- | :------------------------------------------------ |
| http://localhost:8090       | API Gateway                                       |
| http://localhost:8180/admin | Consola de Keycloak (usuario `admin`, contraseña en `.env`) |

Para bajar el stack: `docker compose down`. Agrega `-v` para borrar también la base de datos de Keycloak.

### Variables de entorno (`.env`)

| Variable                   | Por defecto              | Descripción                                          |
| :------------------------- | :----------------------- | :--------------------------------------------------- |
| `GATEWAY_HOST_PORT`        | `8090`                   | Puerto del gateway en el host                         |
| `KEYCLOAK_HOST_PORT`       | `8180`                   | Puerto de Keycloak en el host                         |
| `KEYCLOAK_PUBLIC_URL`      | `http://localhost:8180`  | URL pública de Keycloak (define el claim `iss`)       |
| `KEYCLOAK_REALM`           | `nur`                    | Realm de la aplicación                                |
| `KEYCLOAK_CLIENT_ID`       | `api-gateway`            | Client confidencial usado por `/api/login`            |
| `KEYCLOAK_CLIENT_SECRET`   | —                        | Secreto del client (compartido por gateway e init)    |
| `KC_ADMIN_USERNAME` / `KC_ADMIN_PASSWORD` | `admin` / — | Administrador de la consola de Keycloak         |
| `KC_DB_NAME` / `KC_DB_USERNAME` / `KC_DB_PASSWORD` | `keycloak` / `keycloak` / — | PostgreSQL de Keycloak |
| `USERS_PASSWORD`           | `Admin789456*`           | Contraseña de los usuarios de la aplicación           |

> Si cambias `KEYCLOAK_HOST_PORT`, ajusta también `KEYCLOAK_PUBLIC_URL`.

## 4. Credenciales de prueba

Los crea automáticamente el script `keycloak/init-keycloak.sh` en el realm `nur`:

| Usuario    | Contraseña     |
| :--------- | :------------- |
| `lhurtado` | `Admin789456*` |
| `grobles`  | `Admin789456*` |
| `amolina`  | `Admin789456*` |
| `ccuelar`  | `Admin789456*` |
| `aavila`   | `Admin789456*` |

## 5. Uso

### 5.1 Obtener el token

```bash
curl -X POST http://localhost:8090/api/login \
  -H "Content-Type: application/json" \
  -d '{"username":"lhurtado","password":"Admin789456*"}'
```

```json
{ "access_token": "eyJhbGciOiJSUzI1NiIs...", "token_type": "Bearer", "expires_in": 1800 }
```

El token dura 30 minutos.

### 5.2 Consumir las rutas protegidas

```bash
TOKEN=$(curl -s -X POST http://localhost:8090/api/login \
  -H "Content-Type: application/json" \
  -d '{"username":"lhurtado","password":"Admin789456*"}' | sed -E 's/.*"access_token":"([^"]+)".*/\1/')

curl http://localhost:8090/api/users -H "Authorization: Bearer $TOKEN"
curl http://localhost:8090/api/posts -H "Authorization: Bearer $TOKEN"
```

PowerShell:

```powershell
$body  = @{ username = "lhurtado"; password = "Admin789456*" } | ConvertTo-Json
$token = (Invoke-RestMethod -Method Post -Uri http://localhost:8090/api/login -ContentType "application/json" -Body $body).access_token
Invoke-RestMethod -Uri http://localhost:8090/api/users -Headers @{ Authorization = "Bearer $token" }
```

### 5.3 Respuestas de error

| Caso                                   | HTTP  | Body                                                        |
| :------------------------------------- | :---: | :---------------------------------------------------------- |
| Ruta protegida sin token o con token inválido/expirado | `401` | `{"error":"unauthorized", ...}`               |
| Login con credenciales incorrectas     | `401` | `{"error":"invalid_credentials", ...}`                      |
| Login sin `username` o `password`      | `400` | —                                                           |
| Keycloak no disponible                 | `503` | `{"error":"idp_unavailable", ...}`                          |

### 5.4 Postman

Importa [`postman/nur-apigw.postman_collection.json`](postman/nur-apigw.postman_collection.json).
La petición **Login** guarda el token en la variable `{{token}}`, y las demás peticiones lo usan.

## 6. Decisiones de diseño

- **Spring Cloud Gateway (reactivo, Netty):** las rutas se declaran en
  [`application.yml`](src/main/resources/application.yml) con los filtros
  `RewritePath` (`/api/users` → `/users`) y `RemoveRequestHeader=Authorization`.
- **Keycloak como Identity Provider:** el gateway no guarda usuarios ni firma
  tokens. `POST /api/login` canjea las credenciales con el *Resource Owner
  Password Credentials grant* de OAuth2, que es lo que pide el enunciado. En
  producción se preferiría *Authorization Code + PKCE*.
- **Validación local del JWT:** el gateway es un *OAuth2 Resource Server*.
  Verifica la firma RS256 con las claves públicas (JWKS) del realm, más la
  expiración y el emisor (`iss`). No consulta a Keycloak en cada petición.
- **`KC_HOSTNAME` fijo:** el claim `iss` siempre es `http://localhost:8180/realms/nur`,
  aunque el token se pida por la red interna (`keycloak:8080`). Así el gateway
  acepta tokens obtenidos de las dos formas.
- **Script idempotente:** `init-keycloak.sh` usa `kcadm.sh` y omite lo que ya
  existe. Como Keycloak persiste en PostgreSQL, los arranques siguientes no
  duplican nada.
- **Secretos fuera del repositorio:** `.env` está en `.gitignore`. Solo se
  versiona `.env.example`.

## 7. Estructura

```
nur-apigw/
├── docker-compose.yml
├── Dockerfile                       # multi-stage: maven -> JRE 21 alpine, usuario sin privilegios
├── .env.example
├── keycloak/
│   └── init-keycloak.sh             # realm + client + usuarios
├── postman/
│   └── nur-apigw.postman_collection.json
├── pom.xml
└── src/main/
    ├── java/bo/edu/nur/apigw/
    │   ├── ApiGatewayApplication.java
    │   ├── auth/                    # POST /api/login
    │   └── config/SecurityConfig.java
    └── resources/application.yml    # rutas del gateway
```
