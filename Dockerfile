# Stage 1: Install dependencies in a temporary build image
FROM python:3.10-slim as build

# Set up environment variables to prevent interactive prompts
ENV DEBIAN_FRONTEND=noninteractive

# Remove the problematic APT hook and prevent post-invoke script error
RUN rm -f /etc/apt/apt.conf.d/docker-clean /etc/apt/apt.conf.d/no-cache-clean

# Install curl, git, and docker dependencies without extra recommendations
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    git \
    apt-transport-https \
    ca-certificates \
    gnupg \
    lsb-release && \
    apt-get clean && rm -rf /var/lib/apt/lists/* /var/cache/apt/* /tmp/* /var/tmp/*

# Add Docker’s official GPG key and Docker repository
RUN curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg && \
    echo "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/debian $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list

# Install Docker and clean up cache
RUN apt-get update && apt-get install -y docker.io && \
    apt-get clean && rm -rf /var/lib/apt/lists/* /var/cache/apt/* /tmp/* /var/tmp/*

# Install Docker Compose
RUN curl -L "https://github.com/docker/compose/releases/download/v2.20.0/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose && \
    chmod +x /usr/local/bin/docker-compose

# Install Python packages including Flask, Docker SDK, and GitPython
RUN pip install --no-cache-dir flask docker gitpython

# Stage 2: Copy only required files to the final image
FROM python:3.10-slim

# Set the working directory
WORKDIR /app

# Copy the required Python dependencies from the build stage
COPY --from=build /usr/local/bin/docker-compose /usr/local/bin/docker-compose
COPY --from=build /usr/local/lib/python3.10/site-packages /usr/local/lib/python3.10/site-packages

# Copy the application code to the container
COPY main.py /app/main.py

# Expose the Flask application port
EXPOSE 5000

# Set the entrypoint to run the Flask app
CMD ["python", "/app/main.py"]
