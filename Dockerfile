# Use Python slim as the base image
FROM python:3.10-slim

# Set environment variables to prevent interactive prompts
ENV DEBIAN_FRONTEND=noninteractive

# Disable APT hooks and avoid cache issues
RUN rm -f /etc/apt/apt.conf.d/docker-clean && \
    echo 'APT::Update::Post-Invoke-Success { "echo"; };' > /etc/apt/apt.conf.d/no-cache-clean

# Create a swap file to prevent memory issues during package installation
RUN fallocate -l 2G /swapfile && \
    chmod 600 /swapfile && \
    mkswap /swapfile && \
    swapon /swapfile

# Install dependencies in smaller batches to avoid memory issues
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    apt-transport-https \
    ca-certificates && \
    apt-get install -y gnupg lsb-release && \
    apt-get install -y git && \
    apt-get clean && rm -rf /var/lib/apt/lists/* /var/cache/apt/* /tmp/* /var/tmp/*

# Add Docker’s official GPG key and repository
RUN curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg && \
    echo "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/debian $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list

# Install Docker and Docker Compose
RUN apt-get update && apt-get install -y docker.io && \
    curl -L "https://github.com/docker/compose/releases/download/v2.20.0/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose && \
    chmod +x /usr/local/bin/docker-compose && \
    docker-compose --version && \
    apt-get clean && rm -rf /var/lib/apt/lists/* /var/cache/apt/* /tmp/* /var/tmp/*

# Install Python dependencies
RUN pip install --no-cache-dir flask docker gitpython

# Turn off swap and remove the swap file after installation
RUN swapoff /swapfile && rm -f /swapfile

# Set the working directory
WORKDIR /app

# Copy the application code
COPY main.py /app/main.py

# Expose port 5000
EXPOSE 5000

# Set the entrypoint to run the Flask app
CMD ["python", "/app/main.py"]
