package bo.edu.nur.apigw.auth;

import org.springframework.boot.context.properties.ConfigurationProperties;

/**
 * Datos del client de Keycloak usado por POST /api/login.
 *
 * @param tokenUri     endpoint de tokens del realm (URL interna de la red Docker)
 * @param clientId     client confidencial con "Direct Access Grants" habilitado
 * @param clientSecret secreto del client (viene del .env)
 */
@ConfigurationProperties(prefix = "keycloak")
public record KeycloakProperties(String tokenUri, String clientId, String clientSecret) {
}
