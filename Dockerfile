# Use Python slim as the base image
FROM python:3.10-slim

# Install base dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    git \
    ca-certificates \
    gnupg2 \
    lsb-release \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Install Docker CLI and Docker Compose
RUN curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg && \
    echo "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/debian $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null && \
    apt-get update && apt-get install -y docker.io && apt-get clean && rm -rf /var/lib/apt/lists/*

# Install Docker Compose
RUN curl -L "https://github.com/docker/compose/releases/download/v2.20.0/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose && \
    chmod +x /usr/local/bin/docker-compose && \
    docker-compose --version

# Install Flask and other Python packages
RUN pip install flask docker gitpython

# Set working directory
WORKDIR /app

# Copy the merged Python script into the container
COPY main.py /app/main.py

# Expose port 5000
EXPOSE 5000

# Set the entrypoint to run the Flask app
CMD ["python", "/app/main.py"]
