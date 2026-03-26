# Stage 1: Build the frontend and backend JAR from source
FROM amazoncorretto:21-alpine AS builder

# Install Node.js for the frontend build
RUN apk add --no-cache nodejs npm bash

# Copy the full project
COPY . /workspace
WORKDIR /workspace

# Build the frontend first
WORKDIR /workspace/frontend
RUN npm ci && npm run build

# Copy frontend build output into backend static resources
RUN mkdir -p /workspace/backend/src/main/resources/static && \
    cp -r /workspace/frontend/dist/* /workspace/backend/src/main/resources/static/

# Build the backend JAR
WORKDIR /workspace/backend
RUN chmod +x ./gradlew && \
    ./gradlew bootJar --no-daemon -x test

# Stage 2: Analyze module dependencies for a minimal JRE
FROM amazoncorretto:21-alpine AS corretto-deps

COPY --from=builder /workspace/backend/build/libs/gitactionboard.jar /app/

RUN unzip /app/gitactionboard.jar -d temp && \
    jdeps \
      --print-module-deps \
      --ignore-missing-deps \
      --recursive \
      --multi-release 17 \
      --class-path="./temp/BOOT-INF/lib/*" \
      --module-path="./temp/BOOT-INF/lib/*" \
      /app/gitactionboard.jar > /modules.txt

# Stage 3: Build a custom minimal JRE
FROM amazoncorretto:21-alpine AS corretto-jdk

COPY --from=corretto-deps /modules.txt /modules.txt

# hadolint ignore=DL3018
RUN apk add --no-cache binutils && \
    jlink \
         --verbose \
         --add-modules "$(cat /modules.txt),jdk.crypto.ec,jdk.crypto.cryptoki,jdk.management" \
         --strip-debug \
         --no-man-pages \
         --no-header-files \
         --compress=2 \
         --output /jre

# Stage 4: Final minimal runtime image
# Replace the last stage with:
FROM amazoncorretto:21-alpine

RUN apk upgrade libssl3 libcrypto3

EXPOSE 8080

COPY --from=builder /workspace/backend/build/libs/gitactionboard.jar /app/
WORKDIR /app

CMD ["java", "-jar", "gitactionboard.jar"]

