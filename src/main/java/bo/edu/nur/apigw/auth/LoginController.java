package bo.edu.nur.apigw.auth;

import jakarta.validation.Valid;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.util.LinkedMultiValueMap;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.reactive.function.BodyInserters;
import org.springframework.web.reactive.function.client.WebClient;
import org.springframework.web.reactive.function.client.WebClientResponseException;
import reactor.core.publisher.Mono;

import java.util.Map;

/**
 * POST /api/login
 *
 * Recibe {"username","password"} y los canjea en Keycloak por un access token
 * (OAuth2 Resource Owner Password Credentials grant). El cliente nunca habla
 * directo con Keycloak: el gateway es el unico punto de entrada.
 */
@RestController
@RequestMapping("/api")
public class LoginController {

    private final KeycloakProperties keycloak;
    private final WebClient webClient;

    public LoginController(KeycloakProperties keycloak, WebClient.Builder webClientBuilder) {
        this.keycloak = keycloak;
        this.webClient = webClientBuilder.build();
    }

    @PostMapping(value = "/login", consumes = MediaType.APPLICATION_JSON_VALUE,
            produces = MediaType.APPLICATION_JSON_VALUE)
    public Mono<ResponseEntity<Map<String, Object>>> login(@Valid @RequestBody LoginRequest request) {
        var form = new LinkedMultiValueMap<String, String>();
        form.add("grant_type", "password");
        form.add("client_id", keycloak.clientId());
        form.add("client_secret", keycloak.clientSecret());
        form.add("username", request.username());
        form.add("password", request.password());
        form.add("scope", "openid");

        return webClient.post()
                .uri(keycloak.tokenUri())
                .contentType(MediaType.APPLICATION_FORM_URLENCODED)
                .body(BodyInserters.fromFormData(form))
                .retrieve()
                .bodyToMono(KeycloakTokenResponse.class)
                .map(token -> ResponseEntity.ok(Map.<String, Object>of(
                        "access_token", token.access_token(),
                        "token_type", "Bearer",
                        "expires_in", token.expires_in())))
                .onErrorResume(WebClientResponseException.class, ex -> Mono.just(
                        // Keycloak responde 401 (invalid_grant) ante credenciales erroneas
                        ex.getStatusCode() == HttpStatus.UNAUTHORIZED || ex.getStatusCode() == HttpStatus.BAD_REQUEST
                                ? error(HttpStatus.UNAUTHORIZED, "invalid_credentials", "Usuario o contrasena incorrectos")
                                : error(HttpStatus.BAD_GATEWAY, "idp_error", "Keycloak respondio " + ex.getStatusCode().value())))
                // Cualquier otro error (DNS, conexion rechazada, timeout)
                .onErrorResume(ex -> Mono.just(
                        error(HttpStatus.SERVICE_UNAVAILABLE, "idp_unavailable", "No se pudo contactar a Keycloak")));
    }

    private static ResponseEntity<Map<String, Object>> error(HttpStatus status, String code, String message) {
        return ResponseEntity.status(status).body(Map.of("error", code, "message", message));
    }

    /** Subconjunto de la respuesta del token endpoint de Keycloak. */
    record KeycloakTokenResponse(String access_token, long expires_in) {
    }
}
