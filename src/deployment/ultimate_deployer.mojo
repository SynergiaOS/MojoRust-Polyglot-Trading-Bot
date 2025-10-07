# Ultimate Deployment System
# 🚀 Ultimate Trading Bot - Production Deployment

from python import Python
from os import getenv, system
from json import loads, dumps
from pathlib import Path
from time import now, sleep
from subprocess import run, PIPE
from utils.config_manager import ConfigManager
from monitoring.telegram_notifier import TelegramNotifier
from collections import Dict, List

# Deployment Components
@value
struct DeploymentConfig:
    var environment: String
    var server_host: String
    var server_user: String
    var server_path: String
    var port: Int
    var ssl_enabled: Bool
    var backup_enabled: Bool
    var monitoring_enabled: Bool
    var auto_restart: Bool
    var health_check_interval: Float64
    var max_memory_mb: Int
    var max_cpu_percent: Float32

@value
struct DeploymentStatus:
    var deployed: Bool
    var version: String
    var deployment_time: Float64
    var uptime: Float64
    var health_status: String
    var last_restart: Float64
    var restart_count: Int
    var error_count: Int
    var memory_usage: Float32
    var cpu_usage: Float32
    var active_connections: Int

@value
struct HealthCheck:
    var service_name: String
    var endpoint: String
    var expected_status: Int
    var timeout: Float64
    var last_check: Float64
    var status: String
    var response_time: Float64
    var error_message: String

# Ultimate Deployer
struct UltimateDeployer:
    var config: ConfigManager
    var notifier: TelegramNotifier
    var deployment_config: DeploymentConfig
    var deployment_status: DeploymentStatus
    var health_checks: List[HealthCheck]
    var deployment_log: List[Dict[String, Any]]
    var backup_dir: String
    var local_repo_path: String

    fn __init__(inout self, config: ConfigManager, notifier: TelegramNotifier) raises:
        self.config = config
        self.notifier = notifier
        self.deployment_config = self._load_deployment_config()
        self.deployment_status = self._initialize_deployment_status()
        self.health_checks = self._initialize_health_checks()
        self.deployment_log = List[Dict[String, Any]]()
        self.backup_dir = f"{self.local_repo_path}/backups"
        self.local_repo_path = "/home/marcin/Projects/MojoRust"

        print("🚀 Ultimate Deployer initialized")
        print(f"   Environment: {self.deployment_config.environment}")
        print(f"   Server: {self.deployment_config.server_host}")
        print(f"   SSL Enabled: {self.deployment_config.ssl_enabled}")

    fn _load_deployment_config(inout self) -> DeploymentConfig:
        return DeploymentConfig(
            environment=self.config.get_string("deployment.environment", "production"),
            server_host=self.config.get_string("deployment.server_host", "38.242.239.150"),
            server_user=self.config.get_string("deployment.server_user", "root"),
            server_path=self.config.get_string("deployment.server_path", "/root/mojorust"),
            port=self.config.get_int("deployment.port", 8080),
            ssl_enabled=self.config.get_bool("deployment.ssl_enabled", True),
            backup_enabled=self.config.get_bool("deployment.backup_enabled", True),
            monitoring_enabled=self.config.get_bool("deployment.monitoring_enabled", True),
            auto_restart=self.config.get_bool("deployment.auto_restart", True),
            health_check_interval=self.config.get_float("deployment.health_check_interval", 30.0),
            max_memory_mb=self.config.get_int("deployment.max_memory_mb", 2048),
            max_cpu_percent=self.config.get_float("deployment.max_cpu_percent", 80.0)
        )

    fn _initialize_deployment_status(inout self) -> DeploymentStatus:
        return DeploymentStatus(
            deployed=False,
            version="ULTIMATE-1.0.0",
            deployment_time=0.0,
            uptime=0.0,
            health_status="STOPPED",
            last_restart=0.0,
            restart_count=0,
            error_count=0,
            memory_usage=0.0,
            cpu_usage=0.0,
            active_connections=0
        )

    fn _initialize_health_checks(inout self) -> List[HealthCheck]:
        var checks = List[HealthCheck]()

        checks.append(HealthCheck(
            service_name="Main Service",
            endpoint=f"http://localhost:{self.deployment_config.port}/health",
            expected_status=200,
            timeout=5.0,
            last_check=0.0,
            status="UNKNOWN",
            response_time=0.0,
            error_message=""
        ))

        checks.append(HealthCheck(
            service_name="Data Pipeline",
            endpoint=f"http://localhost:{self.deployment_config.port}/data/health",
            expected_status=200,
            timeout=3.0,
            last_check=0.0,
            status="UNKNOWN",
            response_time=0.0,
            error_message=""
        ))

        return checks

    fn deploy_ultimate_system(inout self) async -> Bool raises:
        print("🚀 Starting Ultimate Trading Bot Deployment...")

        try:
            # 1. Create backup
            if self.deployment_config.backup_enabled:
                await self._create_backup()

            # 2. Build deployment package
            var package_path = await self._build_deployment_package()

            # 3. Deploy to server
            var deployment_success = await self._deploy_to_server(package_path)

            if deployment_success:
                # 4. Start services
                await self._start_services()

                # 5. Verify deployment
                var verification_success = await self._verify_deployment()

                if verification_success:
                    # 6. Update deployment status
                    self._update_deployment_status()

                    # 7. Send deployment success alert
                    await self._send_deployment_alert("SUCCESS")

                    print("✅ Ultimate Trading Bot deployed successfully!")
                    return True
                else:
                    await self._send_deployment_alert("VERIFICATION_FAILED")
                    print("❌ Deployment verification failed")
                    return False
            else:
                await self._send_deployment_alert("DEPLOYMENT_FAILED")
                print("❌ Deployment to server failed")
                return False

        except e:
            await self._send_deployment_alert("ERROR", str(e))
            print(f"❌ Deployment error: {e}")
            return False

    fn _create_backup(inout self) async:
        print("💾 Creating deployment backup...")

        var timestamp = int(now())
        var backup_name = f"mojorust-ultimate-backup-{timestamp}"
        var backup_path = f"{self.backup_dir}/{backup_name}"

        # Create backup directory
        system(f"mkdir -p {self.backup_path}")

        # Backup source code
        system(f"cp -r {self.local_repo_path}/src {backup_path}/")
        system(f"cp -r {self.local_repo_path}/config {backup_path}/")

        # Backup deployment package if exists
        var current_package = f"{self.local_repo_path}/mojorust-ultimate-deploy.tar.gz"
        if Path(current_package).exists():
            system(f"cp {current_package} {backup_path}/")

        print(f"✅ Backup created: {backup_path}")

    fn _build_deployment_package(inout self) async -> String:
        print("📦 Building Ultimate deployment package...")

        var package_name = f"mojorust-ultimate-deploy-{int(now())}.tar.gz"
        var package_path = f"{self.local_repo_path}/{package_name}"

        # Create temporary build directory
        var build_dir = f"{self.local_repo_path}/build"
        system(f"rm -rf {build_dir}")
        system(f"mkdir -p {build_dir}")

        # Copy essential files
        system(f"cp -r {self.local_repo_path}/src {build_dir}/")
        system(f"cp -r {self.local_repo_path}/config {build_dir}/")
        system(f"cp {self.local_repo_path}/.env {build_dir}/" if Path(f"{self.local_repo_path}/.env").exists() else "")
        system(f"cp {self.local_repo_path}/requirements.txt {build_dir}/" if Path(f"{self.local_repo_path}/requirements.txt").exists() else "")

        # Create deployment scripts
        await self._create_deployment_scripts(build_dir)

        # Create package
        system(f"cd {build_dir} && tar -czf {package_path} .")

        # Clean up build directory
        system(f"rm -rf {build_dir}")

        print(f"✅ Deployment package created: {package_path}")
        return package_path

    fn _create_deployment_scripts(inout self, build_dir: String) async:
        # Create start script
        var start_script = f"""#!/bin/bash
# Ultimate Trading Bot Start Script

echo "🚀 Starting Ultimate Trading Bot..."

# Set environment
export PYTHONPATH="${{PYTHONPATH}}:/root/mojorust"
export MOJORUST_ENV={self.deployment_config.environment}
export MOJORUST_PORT={self.deployment_config.port}

# Navigate to deployment directory
cd /root/mojorust

# Start main service
echo "📊 Starting main trading service..."
python3 -m uvicorn src.main_ultimate:app --host 0.0.0.0 --port {self.deployment_config.port} --workers 1 &

# Start monitoring service (if enabled)
if [ "{self.deployment_config.monitoring_enabled}" = "True" ]; then
    echo "📈 Starting monitoring service..."
    python3 -m uvicorn src.monitoring.ultimate_monitor:monitor_app --host 0.0.0.0 --port {self.deployment_config.port + 1} --workers 1 &
fi

echo "✅ Ultimate Trading Bot started successfully!"
echo "🌐 Main service: http://0.0.0.0:{self.deployment_config.port}"
echo "📊 Monitoring: http://0.0.0.0:{self.deployment_config.port + 1}"

# Store process IDs
echo $! > /tmp/mojorust_main.pid
echo $! > /tmp/mojorust_monitor.pid

# Wait a moment and check if services are running
sleep 5

if pgrep -f "main_ultimate" > /dev/null; then
    echo "✅ Main service is running"
else
    echo "❌ Main service failed to start"
    exit 1
fi

if pgrep -f "ultimate_monitor" > /dev/null; then
    echo "✅ Monitoring service is running"
else
    echo "⚠️ Monitoring service not running (disabled or failed)"
fi
"""

        # Create stop script
        var stop_script = """#!/bin/bash
# Ultimate Trading Bot Stop Script

echo "🛑 Stopping Ultimate Trading Bot..."

# Kill main service
if [ -f /tmp/mojorust_main.pid ]; then
    MAIN_PID=$(cat /tmp/mojorust_main.pid)
    if kill -0 $MAIN_PID 2>/dev/null; then
        echo "Stopping main service (PID: $MAIN_PID)..."
        kill $MAIN_PID
        sleep 2
        if kill -0 $MAIN_PID 2>/dev/null; then
            echo "Force killing main service..."
            kill -9 $MAIN_PID
        fi
    fi
    rm -f /tmp/mojorust_main.pid
fi

# Kill monitoring service
if [ -f /tmp/mojorust_monitor.pid ]; then
    MONITOR_PID=$(cat /tmp/mojorust_monitor.pid)
    if kill -0 $MONITOR_PID 2>/dev/null; then
        echo "Stopping monitoring service (PID: $MONITOR_PID)..."
        kill $MONITOR_PID
        sleep 2
        if kill -0 $MONITOR_PID 2>/dev/null; then
            echo "Force killing monitoring service..."
            kill -9 $MONITOR_PID
        fi
    fi
    rm -f /tmp/mojorust_monitor.pid
fi

# Kill any remaining processes
pkill -f "main_ultimate" 2>/dev/null || true
pkill -f "ultimate_monitor" 2>/dev/null || true

echo "✅ Ultimate Trading Bot stopped"
"""

        # Create health check script
        var health_script = f"""#!/bin/bash
# Ultimate Trading Bot Health Check

echo "🔍 Performing health check..."

# Check if main service is running
if pgrep -f "main_ultimate" > /dev/null; then
    echo "✅ Main service is running"
    MAIN_STATUS="healthy"
else
    echo "❌ Main service is not running"
    MAIN_STATUS="unhealthy"
fi

# Check monitoring service
if pgrep -f "ultimate_monitor" > /dev/null; then
    echo "✅ Monitoring service is running"
    MONITOR_STATUS="healthy"
else
    echo "⚠️ Monitoring service is not running"
    MONITOR_STATUS="unhealthy"
fi

# Check memory usage
MEMORY_USAGE=$(ps aux | grep -E "main_ultimate|ultimate_monitor" | awk '{{sum+=$6}} END {{print sum/1024}}')
echo "💾 Memory usage: ${{MEMORY_USAGE}}MB"

# Check CPU usage
CPU_USAGE=$(top -bn1 | grep -E "main_ultimate|ultimate_monitor" | awk '{{sum+=$9}} END {{print sum}}')
echo "💻 CPU usage: ${{CPU_USAGE}}%"

# Check port availability
if netstat -tuln | grep ":{self.deployment_config.port}" > /dev/null; then
    echo "🌐 Port {self.deployment_config.port} is open"
    PORT_STATUS="open"
else
    echo "❌ Port {self.deployment_config.port} is closed"
    PORT_STATUS="closed"
fi

# Overall status
if [[ "$MAIN_STATUS" == "healthy" && "$PORT_STATUS" == "open" ]]; then
    echo "✅ Overall status: HEALTHY"
    exit 0
else
    echo "❌ Overall status: UNHEALTHY"
    exit 1
fi
"""

        # Write scripts to files
        with open(f"{build_dir}/start.sh", "w") as f:
            f.write(start_script)

        with open(f"{build_dir}/stop.sh", "w") as f:
            f.write(stop_script)

        with open(f"{build_dir}/health_check.sh", "w") as f:
            f.write(health_script)

        # Make scripts executable
        system(f"chmod +x {build_dir}/start.sh")
        system(f"chmod +x {build_dir}/stop.sh")
        system(f"chmod +x {build_dir}/health_check.sh")

        print("✅ Deployment scripts created")

    fn _deploy_to_server(inout self, package_path: String) async -> Bool:
        print(f"📡 Deploying to {self.deployment_config.server_host}...")

        try:
            # Create deployment directory
            var create_dir_cmd = f"ssh {self.deployment_config.server_user}@{self.deployment_config.server_host} 'mkdir -p {self.deployment_config.server_path}'"
            run(create_dir_cmd, shell=True, check=True)

            # Upload deployment package
            var upload_cmd = f"scp {package_path} {self.deployment_config.server_user}@{self.deployment_config.server_host}:{self.deployment_config.server_path}/"
            run(upload_cmd, shell=True, check=True)

            # Extract package on server
            var extract_cmd = f"ssh {self.deployment_config.server_user}@{self.deployment_config.server_host} 'cd {self.deployment_config.server_path} && tar -xzf $(basename {package_path}) && rm $(basename {package_path})'"
            run(extract_cmd, shell=True, check=True)

            # Install dependencies
            var install_cmd = f"ssh {self.deployment_config.server_user}@{self.deployment_config.server_host} 'cd {self.deployment_config.server_path} && pip3 install -r requirements.txt 2>/dev/null || true'"
            run(install_cmd, shell=True, check=True)

            print("✅ Successfully deployed to server")
            return True

        except e:
            print(f"❌ Deployment to server failed: {e}")
            return False

    fn _start_services(inout self) async:
        print("🚀 Starting Ultimate Trading Bot services...")

        var start_cmd = f"ssh {self.deployment_config.server_user}@{self.deployment_config.server_host} 'cd {self.deployment_config.server_path} && ./start.sh'"
        run(start_cmd, shell=True, check=True)

        # Wait for services to start
        sleep(10)

        print("✅ Services started")

    fn _verify_deployment(inout self) async -> Bool:
        print("🔍 Verifying deployment...")

        try:
            # Run health check on server
            var health_cmd = f"ssh {self.deployment_config.server_user}@{self.deployment_config.server_host} 'cd {self.deployment_config.server_path} && ./health_check.sh'"
            var result = run(health_cmd, shell=True, capture_output=True, text=True)

            if result.returncode == 0:
                print("✅ Health check passed")
                print(result.stdout)

                # Test API endpoints
                var api_test = await self._test_api_endpoints()
                return api_test
            else:
                print("❌ Health check failed")
                print(result.stderr)
                return False

        except e:
            print(f"❌ Deployment verification failed: {e}")
            return False

    fn _test_api_endpoints(inout self) async -> Bool:
        print("🌐 Testing API endpoints...")

        try:
            # Test main endpoint
            var main_endpoint = f"http://{self.deployment_config.server_host}:{self.deployment_config.port}/health"
            var response = run(f"curl -s -o /dev/null -w '%{{http_code}}' {main_endpoint}", shell=True, capture_output=True, text=True)

            if response.stdout.strip() == "200":
                print("✅ Main API endpoint is responding")
                return True
            else:
                print(f"❌ Main API endpoint returned: {response.stdout.strip()}")
                return False

        except e:
            print(f"❌ API endpoint testing failed: {e}")
            return False

    fn _update_deployment_status(inout self):
        self.deployment_status.deployed = True
        self.deployment_status.deployment_time = now()
        self.deployment_status.health_status = "RUNNING"
        self.deployment_status.restart_count = 0
        self.deployment_status.error_count = 0

    fn _send_deployment_alert(inout self, status: String, error_message: String = "") async:
        var message = f"🚀 **ULTIMATE TRADING BOT DEPLOYMENT** 🚀\n\n"

        if status == "SUCCESS":
            message += "✅ **DEPLOYMENT SUCCESSFUL**\n\n"
            message += f"Environment: {self.deployment_config.environment}\n"
            message += f"Server: {self.deployment_config.server_host}\n"
            message += f"Port: {self.deployment_config.port}\n"
            message += f"Version: {self.deployment_status.version}\n"
            message += f"Time: {now()}\n\n"
            message += "🌐 Services:\n"
            message += f"Main: http://{self.deployment_config.server_host}:{self.deployment_config.port}\n"
            if self.deployment_config.monitoring_enabled:
                message += f"Monitor: http://{self.deployment_config.server_host}:{self.deployment_config.port + 1}\n"

        elif status == "VERIFICATION_FAILED":
            message += "❌ **DEPLOYMENT VERIFICATION FAILED**\n\n"
            message += "The deployment completed but health checks failed.\n"
            message += "Please check the server logs for details."

        elif status == "DEPLOYMENT_FAILED":
            message += "❌ **DEPLOYMENT FAILED**\n\n"
            message += "Failed to deploy the package to the server.\n"
            message += "Please check the deployment logs."

        elif status == "ERROR":
            message += "🚨 **DEPLOYMENT ERROR**\n\n"
            message += f"Error: {error_message}\n"
            message += "Please check the deployment configuration."

        await self.notifier.send_custom_message(message)

    fn start_monitoring(inout self):
        print("📊 Starting deployment monitoring...")

        while self.deployment_status.deployed:
            try:
                # Perform health checks
                await self._perform_health_checks()

                # Check system resources
                await self._check_system_resources()

                # Auto-restart if needed
                if self.deployment_config.auto_restart:
                    await self._auto_restart_if_needed()

                # Wait before next check
                sleep(self.deployment_config.health_check_interval)

            except e:
                print(f"Monitoring error: {e}")
                sleep(10)

    fn _perform_health_checks(inout self) async:
        for check in self.health_checks:
            try:
                var start_time = now()
                var response = run(f"curl -s -o /dev/null -w '%{{http_code}}' {check.endpoint}", shell=True, capture_output=True, text=True, timeout=check.timeout)
                var response_time = (now() - start_time) * 1000

                check.last_check = now()
                check.response_time = response_time

                if response.stdout.strip() == str(check.expected_status):
                    check.status = "HEALTHY"
                    check.error_message = ""
                else:
                    check.status = "UNHEALTHY"
                    check.error_message = f"HTTP {response.stdout.strip()} (expected {check.expected_status})"

                    # Send alert for unhealthy service
                    await self.notifier.send_custom_message(f"🚨 **SERVICE UNHEALTHY** 🚨\n\nService: {check.service_name}\nStatus: {check.status}\nError: {check.error_message}")

            except e:
                check.status = "ERROR"
                check.error_message = str(e)
                check.last_check = now()

                await self.notifier.send_custom_message(f"🚨 **SERVICE ERROR** 🚨\n\nService: {check.service_name}\nError: {check.error_message}")

    fn _check_system_resources(inout self) async:
        try:
            # Get system metrics from server
            var cmd = f"ssh {self.deployment_config.server_user}@{self.deployment_config.server_host} 'cd {self.deployment_config.server_path} && ./health_check.sh'"
            var result = run(cmd, shell=True, capture_output=True, text=True)

            if result.returncode == 0:
                # Parse metrics from output (simplified)
                self.deployment_status.health_status = "RUNNING"
            else:
                self.deployment_status.health_status = "UNHEALTHY"
                self.deployment_status.error_count += 1

                if self.deployment_status.error_count > 3:
                    await self.notifier.send_custom_message("🚨 **SYSTEM UNHEALTHY** 🚨\n\nMultiple health check failures detected.")

        except e:
            print(f"System resource check failed: {e}")

    fn _auto_restart_if_needed(inout self) async:
        if (self.deployment_status.health_status == "UNHEALTHY" and
            self.deployment_status.error_count > 5):

            print("🔄 Attempting automatic restart...")

            try:
                # Stop services
                var stop_cmd = f"ssh {self.deployment_config.server_user}@{self.deployment_config.server_host} 'cd {self.deployment_config.server_path} && ./stop.sh'"
                run(stop_cmd, shell=True, check=True)

                sleep(5)

                # Start services
                var start_cmd = f"ssh {self.deployment_config.server_user}@{self.deployment_config.server_host} 'cd {self.deployment_config.server_path} && ./start.sh'"
                run(start_cmd, shell=True, check=True)

                self.deployment_status.last_restart = now()
                self.deployment_status.restart_count += 1
                self.deployment_status.error_count = 0

                await self.notifier.send_custom_message(f"🔄 **AUTOMATIC RESTART** 🔄\n\nServices restarted automatically.\nRestart count: {self.deployment_status.restart_count}")

            except e:
                await self.notifier.send_custom_message(f"🚨 **AUTO-RESTART FAILED** 🚨\n\nError: {str(e)}")

    fn get_deployment_status(inout self) -> Dict[String, Any]:
        return {
            "environment": self.deployment_config.environment,
            "deployed": self.deployment_status.deployed,
            "version": self.deployment_status.version,
            "uptime": now() - self.deployment_status.deployment_time if self.deployment_status.deployed else 0,
            "health_status": self.deployment_status.health_status,
            "restart_count": self.deployment_status.restart_count,
            "error_count": self.deployment_status.error_count,
            "last_restart": self.deployment_status.last_restart,
            "services": [
                {
                    "name": check.service_name,
                    "status": check.status,
                    "last_check": check.last_check,
                    "response_time": check.response_time
                } for check in self.health_checks
            ]
        }