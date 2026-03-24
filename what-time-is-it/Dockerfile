FROM eclipse-temurin:11-jdk-alpine
WORKDIR /work
COPY . /work
RUN ./mvnw package

FROM eclipse-temurin:11-jdk-alpine
WORKDIR /root
COPY --from=0 /work/target/what-time-is-it-0.0.1-jar-with-dependencies.jar what-time-is-it.jar
CMD ["java", "-jar", "what-time-is-it.jar"]
