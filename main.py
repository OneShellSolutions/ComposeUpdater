from flask import Flask, jsonify, send_file
from flask_cors import CORS  # Import CORS
import requests
import docker
import os
import zipfile
import time
import subprocess
import threading
import git
import shutil
import logging
import yaml

app = Flask(__name__)

# Initialize CORS to allow all origins
CORS(app)  # This will allow requests from any origin

# Initialize Docker client
client = docker.DockerClient(base_url='unix://var/run/docker.sock')

# Logging setup
logging.basicConfig(level=logging.INFO)

REPO_DIR = "/app/repo"
COMPOSE_FILE_PATH = os.getenv('COMPOSE_FILE_PATH', 'docker-compose.yaml')
GITHUB_REPO_URL = os.getenv('GITHUB_REPO_URL', 'https://github.com/OneShellSolutions/PosDeployment.git')

logging.basicConfig(level=logging.INFO, format='[%(asctime)s] %(levelname)s: %(message)s')


def get_host_path_for_app_data():
    client = docker.DockerClient(base_url='unix://var/run/docker.sock')
    container = client.containers.get("compose-updater")
    for mount in container.attrs["Mounts"]:
        if mount["Destination"] == "/app/data":
            logging.info(f"Detected host path for /app/data: {mount['Source']}")
            return mount["Source"]
    raise RuntimeError("Could not find /app/data mount")


def patch_volume_paths(compose_path, host_data_path):
    with open(compose_path, 'r') as f:
        data = yaml.safe_load(f)

    replacements = []
    for svc_name, svc in data.get("services", {}).items():
        if "volumes" in svc:
            new_volumes = []
            for vol in svc["volumes"]:
                if isinstance(vol, str):
                    host, sep, container = vol.partition(":")
                    if host.startswith("/app/data"):
                        real_host = host.replace("/app/data", host_data_path)
                        new_volumes.append(f"{real_host}:{container}")
                        replacements.append((svc_name, host, real_host))
                        logging.info(f"[PATCH] {svc_name}: {host} → {real_host}")
                    else:
                        new_volumes.append(vol)
                else:
                    new_volumes.append(vol)
            svc["volumes"] = new_volumes

    patched_path = compose_path.replace(".yaml", ".patched.yaml")
    with open(patched_path, 'w') as f:
        yaml.safe_dump(data, f)

    logging.info(f"✔️ Patched compose file saved: {patched_path}")
    return patched_path


def stop_conflicting_containers(names):
    for name in names:
        result = subprocess.run(
            ["docker", "ps", "-a", "-q", "-f", f"name=^{name}$"],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True
        )
        container_id = result.stdout.strip()
        if container_id:
            logging.info(f"Stopping/removing container: {name}")
            subprocess.run(["docker", "stop", container_id], check=True)
            subprocess.run(["docker", "rm", container_id], check=True)


def pull_and_apply_compose():
    try:
        if os.path.exists(REPO_DIR):
            if os.path.isdir(REPO_DIR):
                try:
                    repo = git.Repo(REPO_DIR)
                    logging.info(f"Using existing Git repo: {REPO_DIR}")
                except git.exc.InvalidGitRepositoryError:
                    shutil.rmtree(REPO_DIR)
                    repo = git.Repo.clone_from(GITHUB_REPO_URL, REPO_DIR)
            else:
                logging.error("REPO_DIR exists but is not a directory.")
                return
        else:
            logging.info("Cloning Git repo...")
            repo = git.Repo.clone_from(GITHUB_REPO_URL, REPO_DIR)

        repo.remotes.origin.fetch()
        current = repo.head.commit
        latest = repo.remotes.origin.refs.master.commit

        if current != latest:
            logging.info("Repo updated. Pulling new commit.")
            repo.git.reset("--hard", "origin/master")
            repo.remotes.origin.pull('master')

            stop_conflicting_containers([
                'nats-server', 'PosPythonBackend', 'watchtower',
                'mongodb', 'posNodeBackend', 'posbackend', 'posFrontend'
            ])

            host_data_path = get_host_path_for_app_data()
            patched_file = patch_volume_paths(f"{REPO_DIR}/{COMPOSE_FILE_PATH}", host_data_path)

            # Copy the config file from the repo to a host-visible mount using `cp`
            source_conf = "/app/repo/nats-server.conf"
            target_conf = "/app/data/repo/nats/nats-server.conf"

            try:
                subprocess.run(["mkdir", "-p", "/app/data/repo"], check=True)
                subprocess.run(["cp", "-f", source_conf, target_conf], check=True)
                logging.info(f"✔️ Copied nats-server.conf → {target_conf}")
            except subprocess.CalledProcessError as e:
                logging.warning(f" Failed to copy nats-server.conf: {e}")

            subprocess.run(["docker-compose", "-f", patched_file, "pull"], check=True)
            subprocess.run(["docker-compose", "-f", patched_file, "up", "-d", "--force-recreate"], check=True)
        else:
            logging.info("No changes in repository. Skipping.")
    except Exception as e:
        logging.error(f"❌ Error during update: {e}")


def periodic_check():
    while True:
        logging.info("Starting periodic update check...")
        pull_and_apply_compose()
        logging.info("Waiting for the next update cycle...")
        time.sleep(20)

# Run the periodic check in a separate thread
def start_periodic_check():
    logging.info("Starting periodic check thread...")
    periodic_thread = threading.Thread(target=periodic_check)
    periodic_thread.daemon = True
    periodic_thread.start()

# Health check endpoint
@app.route('/health', methods=['GET'])
def health_check():
    containers = client.containers.list()
    status = {}
    all_services_running = True
    failed_services = []

    for required_service in REQUIRED_SERVICES:
        container_status = next((container.status for container in containers if container.name == required_service), 'not found')
        if container_status != 'running':
            all_services_running = False
            failed_services.append(required_service)
        status[required_service] = container_status


    # Check the health endpoint
    try:
        response = requests.get('http://host.docker.internal:3003/health')
        if response.status_code == 200:
            health_status = response.json().get('status', 'unknown')
            if health_status != 'Pos win exe':
                all_services_running = False
                failed_services.append('Printer Util Failed')
        else:
            all_services_running = False
            failed_services.append('Printer Util Failed')
    except requests.RequestException:
        all_services_running = False
        failed_services.append('Printer Util Failed')


    if not all_services_running:
        print(f"Failed services: {failed_services}")

    if all_services_running:
        return jsonify({"status": "success", "message": "All services are running"}), 200
    else:
        return jsonify({"status": "failure", "message": "One or more services are not running", "details": status, "failed_services": failed_services}), 500
# Logs download endpoint
@app.route('/logs', methods=['GET'])
def download_logs():
    zip_filename = f"/app/logs_{int(time.time())}.zip"
    with zipfile.ZipFile(zip_filename, 'w') as zipf:
        for root, _, files in os.walk(LOG_DIR):
            for file in files:
                if file not in EXCLUDED_LOGS:
                    file_path = os.path.join(root, file)
                    zipf.write(file_path, arcname=file)
    return send_file(zip_filename, as_attachment=True)

# Get CPU and memory usage of a container
def get_cpu_memory_usage(container):
    stats = container.stats(stream=False)
    
    # Calculate CPU usage
    cpu_delta = stats['cpu_stats']['cpu_usage']['total_usage'] - stats['precpu_stats']['cpu_usage']['total_usage']
    system_delta = stats['cpu_stats']['system_cpu_usage'] - stats['precpu_stats']['system_cpu_usage']
    num_cpus = len(stats['cpu_stats']['cpu_usage'].get('percpu_usage', [1]))
    cpu_percentage = (cpu_delta / system_delta) * num_cpus * 100 if system_delta > 0 else 0
    
    # Calculate memory usage
    memory_usage = stats['memory_stats']['usage']
    memory_limit = stats['memory_stats']['limit']
    memory_percentage = (memory_usage / memory_limit) * 100 if memory_limit > 0 else 0
    
    return {
        'cpu_usage': f"{cpu_percentage:.2f}%",
        'memory_usage': f"{memory_usage / (1024 ** 2):.2f} MB",
        'memory_percentage': f"{memory_percentage:.2f}%"
    }

# CPU and memory usage endpoint
@app.route('/cpu-memory-usage', methods=['GET'])
def cpu_memory_usage():
    usage_stats = {}
    containers = client.containers.list()

    for container in containers:
        try:
            usage = get_cpu_memory_usage(container)
            usage_stats[container.name] = usage
        except Exception as e:
            usage_stats[container.name] = f"Error retrieving usage: {str(e)}"
    
    return jsonify(usage_stats)

@app.route('/restart-services', methods=['GET'])
def restart_services_by_names():
    try:
        # Names of the services from docker-compose.yml
        services_to_restart = [
            "posbackend",
            "posNodeBackend",
            "posFrontend",
            "mongodb",
            "nats-server"
        ]

        # Restart each container by name
        for service_name in services_to_restart:
            container = client.containers.get(service_name)
            if container:
                logging.info(f"Restarting container: {service_name}")
                container.restart(timeout=10)  # Gracefully restart with a timeout

        # Wait for all services to be running
        timeout = 300  # Timeout in seconds
        start_time = time.time()
        while time.time() - start_time < timeout:
            containers = client.containers.list()
            statuses = {container.name: container.status for container in containers}

            # Check if all required services are running
            all_running = all(
                statuses.get(service, 'not found') == 'running'
                for service in services_to_restart
            )

            if all_running:
                return jsonify({
                    "status": "success",
                    "message": "All services are running"
                }), 200

            logging.info("Waiting for services to start...")
            time.sleep(5)

        # If timeout is reached
        failed_services = [
            service for service in services_to_restart
            if statuses.get(service, 'not found') != 'running'
        ]
        return jsonify({
            "status": "failure",
            "message": "Timeout reached; some services are not running",
            "failed_services": failed_services
        }), 500

    except Exception as e:
        logging.error(f"Error during service restart: {e}")
        return jsonify({
            "status": "failure",
            "message": f"Error during service restart: {e}"
        }), 500

if __name__ == '__main__':
    start_periodic_check()
    app.run(host='0.0.0.0', port=5000)
