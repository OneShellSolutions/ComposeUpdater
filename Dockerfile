# Use Python slim as the base image
FROM python:3.10-slim

# First step: Update and install curl, git, apt-transport-https, and ca-certificates
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    curl \
    git \
    apt-transport-https \
    ca-certificates && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# Second step: Install gnupg2 and lsb-release
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    gnupg2 \
    lsb-release && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# Third step: Add Docker's official GPG key and Docker repository
RUN curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg && \
    echo "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/debian $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null && \
    apt-get update && rm -rf /var/lib/apt/lists/*

# Fourth step: Install Docker
RUN apt-get update && \
    apt-get install -y --no-install-recommends docker.io && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# Fifth step: Install Docker Compose
RUN curl -L "https://github.com/docker/compose/releases/download/v2.20.0/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose && \
    chmod +x /usr/local/bin/docker-compose && \
    docker-compose --version

# Sixth step: Install Flask and other Python packages
RUN pip install --no-cache-dir flask docker gitpython

# Set working directory
WORKDIR /app

# Copy the merged Python script into the container
COPY main.py /app/main.py

# Expose port 5000
EXPOSE 5000

# Set the entrypoint to run the Flask app
CMD ["python", "/app/main.py"]
