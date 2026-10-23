# =============================================================================
# nur-apigw (API Gateway - Spring Cloud Gateway)
#
# Build multi-stage: separa la descarga de dependencias del compilado para que
# Docker pueda cachear la capa de dependencias (la mas lenta) y solo recompile
# cuando cambia el codigo fuente.
#
# Build:
#   docker build -t luisstrongest/nur-apigw:1.0.0 .
# =============================================================================


# =============================================================================
# STAGE 1: "dependency-cache"
#   Descarga todas las dependencias Maven. Solo se invalida si cambia pom.xml.
# =============================================================================
FROM maven:3.9-eclipse-temurin-21-alpine AS dependency-cache

WORKDIR /build

COPY pom.xml .

RUN mvn dependency:go-offline -B -e


# =============================================================================
# STAGE 2: "builder"
#   Compila y empaqueta el JAR ejecutable (Spring Boot fat-jar).
# =============================================================================
FROM dependency-cache AS builder

COPY src src

RUN mvn package -B -e -DskipTests


# =============================================================================
# STAGE 3: "runtime"
#   Imagen final: solo JRE + el JAR.
# =============================================================================
FROM eclipse-temurin:21-jre-alpine AS runtime

# Usuario sin privilegios
RUN addgroup -S appgroup && adduser -S appuser -G appgroup

WORKDIR /app

COPY --from=builder --chown=appuser:appgroup /build/target/nur-apigw.jar app.jar

USER appuser

EXPOSE 8080

ENV JAVA_OPTS="-XX:+UseContainerSupport -XX:MaxRAMPercentage=75.0"

# wget viene en busybox (alpine): suficiente para el healthcheck
HEALTHCHECK --interval=10s --timeout=3s --start-period=30s --retries=5 \
    CMD wget -qO- http://localhost:8080/actuator/health/readiness || exit 1

ENTRYPOINT ["sh", "-c", "java $JAVA_OPTS -jar app.jar"]
