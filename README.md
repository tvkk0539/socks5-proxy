# SOCKS5 Proxy Auto-Installer

A robust, automated shell script to install and configure a SOCKS5 proxy server on Linux.

## Features

- **Multiple Server Options:** Choose between **Dante** (recommended), **3proxy**, or **microsocks**.
- **Authentication:** Supports Username/Password authentication or IP-based (no auth) access.
- **Robust Binding:** Binds to `0.0.0.0` to handle dynamic internal IP changes (common in cloud environments).
- **Firewall Persistence:** Automatically configures and saves firewall rules (UFW, Firewalld, or iptables-persistent) to survive reboots.
- **Multi-OS Support:** Tested on Ubuntu, Debian, CentOS, Rocky Linux, and AlmaLinux.

## Supported Operating Systems

- Ubuntu 20.04 / 22.04 / 24.04
- Debian 10 / 11 / 12
- CentOS 7 / 8
- Rocky Linux 8 / 9
- AlmaLinux 8 / 9

## Installation

1.  **Download the script** (or create it on your server):
    ```bash
    # Assuming the file is named install-socks5.sh
    chmod +x install-socks5.sh
    ```

2.  **Run as root:**
    ```bash
    sudo ./install-socks5.sh
    ```

3.  **Follow the on-screen prompts:**
    - Select Server Type (Dante is recommended).
    - Choose Port (Default: 1080).
    - Set Username and Password.

## ☁️ Cloud Provider Configuration (IMPORTANT)

If you are hosting this on **AWS, Google Cloud (GCP), Azure, or Oracle Cloud**, you **MUST** open the port (default 1080) in your cloud provider's firewall dashboard. The script only opens the firewall on the server itself.

### Google Cloud Platform (GCP)
1.  Go to **VPC Network** > **Firewall**.
2.  Click **Create Firewall Rule**.
3.  **Name:** `allow-socks5`
4.  **Targets:** `All instances in the network` (or specify target tags).
5.  **Source IPv4 ranges:** `0.0.0.0/0` (allows access from anywhere).
6.  **Protocols and ports:** Check `TCP` and enter `1080`.
7.  Click **Create**.

### AWS EC2
1.  Go to your instance security group.
2.  Edit **Inbound rules**.
3.  Add rule: **Custom TCP**, Port `1080`, Source `0.0.0.0/0`.

## Connecting to the Proxy

After installation, the script will output your connection details.

**Format:**
`socks5://username:password@IP_ADDRESS:PORT`

**Example:**
`socks5://myuser:secret123@123.45.67.89:1080`

### Testing with curl
```bash
curl --socks5 myuser:secret123@123.45.67.89:1080 https://api.ipify.org
```

## Troubleshooting

-   **Connection Refused / Timeout:**
    -   Check if the service is running: `systemctl status danted`
    -   **Verify Cloud Firewall:** This is the most common issue. Ensure port 1080 is open in your cloud provider's console.
-   **Authentication Failed:**
    -   Verify the username and password.
    -   For Dante, config is at `/etc/danted.conf`.
    -   Restart the service after changes: `systemctl restart danted`.
