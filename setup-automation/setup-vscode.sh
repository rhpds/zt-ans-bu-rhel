#!/bin/bash
cd /tmp

curl -k  -L https://${SATELLITE_URL}/pub/katello-server-ca.crt -o /etc/pki/ca-trust/source/anchors/${SATELLITE_URL}.ca.crt
update-ca-trust
rpm -Uhv https://${SATELLITE_URL}/pub/katello-ca-consumer-latest.noarch.rpm || true

subscription-manager status >/dev/null 2>&1 || \
  subscription-manager register --org=${SATELLITE_ORG} --activationkey=${SATELLITE_ACTIVATIONKEY} --force
setenforce 0

# ─── Ensure rhel user has sudo and password ───
echo "rhel:ansible123!" | chpasswd
echo "rhel ALL=(ALL:ALL) NOPASSWD:ALL" > /etc/sudoers.d/rhel_sudoers
chmod 440 /etc/sudoers.d/rhel_sudoers


# ─── Firewall ───
systemctl stop firewalld

# ─── Code-server setup (runs as rhel, opens lab_inventory) ───
systemctl stop code-server || true
[ -f /home/rhel/.config/code-server/config.yaml ] && \
  mv /home/rhel/.config/code-server/config.yaml /home/rhel/.config/code-server/config.bk.yaml || true

mkdir -p /home/rhel/.config/code-server
tee /home/rhel/.config/code-server/config.yaml << 'EOF'
bind-addr: 0.0.0.0:8080
auth: none
cert: false
EOF

# Override code-server to open lab_inventory by default
mkdir -p /etc/systemd/system/code-server.service.d
CODE_SERVER_BIN=$(grep -oP 'ExecStart=\K\S+' /usr/lib/systemd/system/code-server*.service 2>/dev/null | head -1)
CODE_SERVER_BIN=${CODE_SERVER_BIN:-/usr/bin/code-server}
cat > /etc/systemd/system/code-server.service.d/override.conf << EOF
[Service]
ExecStart=
ExecStart=${CODE_SERVER_BIN} /home/rhel/lab_inventory
EOF
systemctl daemon-reload

# Configure VS Code settings: hide dotfiles from explorer
mkdir -p /home/rhel/.local/share/code-server/User
cat > /home/rhel/.local/share/code-server/User/settings.json << 'SETTINGS'
{
  "workbench.colorTheme": "Default Dark+",
  "window.menuBarVisibility": "classic",
  "files.exclude": {
    "**/.ssh": true,
    "**/.config": true,
    "**/.cache": true,
    "**/.local": true,
    "**/.ansible": true,
    "**/.bash_logout": true,
    "**/.bash_profile": true,
    "**/.bashrc": true,
    "**/.ansible-navigator.yml": true
  }
}
SETTINGS

systemctl start code-server || true

# ─── Repo configuration ───
# Re-enable RHSM repo management (AWS images set manage_repos=0)
sed -i 's/^manage_repos.*=.*0/manage_repos = 1/' /etc/rhsm/rhsm.conf

# Disable unreachable AWS RHUI repos
dnf config-manager --set-disabled '*rhui*' 2>/dev/null || true

# Disable Amazon ID dnf plugin that errors in non-AWS environments
if [ -f /etc/dnf/plugins/amazon-id.conf ]; then
    sed -i 's/enabled.*=.*1/enabled=0/' /etc/dnf/plugins/amazon-id.conf
fi

# Enable RHEL 9 repos from satellite
subscription-manager repos --enable=rhel-9-for-x86_64-baseos-rpms --enable=rhel-9-for-x86_64-appstream-rpms

# ─── Install packages ───
dnf install -y unzip nano git podman python3-pip sshpass || true

# Install ansible-core and ansible-navigator via pip (not available via dnf on this image)
export PATH="/usr/local/bin:$PATH"
python3 -m pip install --upgrade pip 2>/dev/null || true
python3 -m pip install ansible-core ansible-navigator 2>/dev/null || true

# Verify ansible-galaxy is available
if ! command -v ansible-galaxy >/dev/null 2>&1; then
  echo "ERROR: ansible-galaxy not found after pip install"
  find / -name ansible-galaxy -type f 2>/dev/null | head -5
  exit 1
fi

# ─── Ansible collections (used across modules 3-7) ───
echo "Installing Ansible collections..."
mkdir -p /home/rhel/.ansible/collections
chown -R rhel:rhel /home/rhel/.ansible
sudo -Hu rhel /usr/local/bin/ansible-galaxy collection install ansible.posix --force
sudo -Hu rhel /usr/local/bin/ansible-galaxy collection install community.general --force

# ─── Lab Inventory Setup ───
echo "Creating lab_inventory for rhel user..."
mkdir -p /home/rhel/lab_inventory

cat > /home/rhel/lab_inventory/hosts << 'INVENTORY'
[web]
node01
node02

[db]
node03

[all:vars]
ansible_user=rhel
ansible_password=ansible123!
ansible_ssh_common_args='-o StrictHostKeyChecking=no'
INVENTORY

cat > /home/rhel/lab_inventory/ansible.cfg << 'ANSIBLECFG'
[defaults]
inventory = hosts
remote_user = rhel
host_key_checking = False
deprecation_warnings = False

[privilege_escalation]
become = True
become_method = sudo
become_user = root
become_ask_pass = False
ANSIBLECFG

# Install ansible.cfg system-wide so EEs can access it via volume mount
mkdir -p /etc/ansible
cp /home/rhel/lab_inventory/ansible.cfg /etc/ansible/ansible.cfg

chown -R rhel:rhel /home/rhel/lab_inventory
chmod 644 /home/rhel/lab_inventory/hosts /home/rhel/lab_inventory/ansible.cfg

# ─── Ansible Navigator Setup (Modules 6+) ───
cat > /home/rhel/.ansible-navigator.yml << 'EOF'
---
ansible-navigator:
  ansible:
    inventory:
      entries:
      - /home/rhel/lab_inventory/hosts

  execution-environment:
    image: quay.io/acme_corp/rhel_90_ee:latest
    enabled: true
    container-engine: podman
    pull:
      policy: missing
    volume-mounts:
    - src: "/etc/ansible/"
      dest: "/etc/ansible/"
    - src: "/home/rhel/.ansible/collections/"
      dest: "/home/rhel/.ansible/collections/"
EOF

chown rhel:rhel /home/rhel/.ansible-navigator.yml
chmod 644 /home/rhel/.ansible-navigator.yml

# Enable linger for rhel user (required for rootless podman)
loginctl enable-linger rhel

# Pre-pull the Execution Environment image (public, no auth needed)
echo "Pulling Execution Environment image..."
podman pull quay.io/acme_corp/rhel_90_ee:latest

# Install ansible-lint
python3 -m pip install ansible-lint >/dev/null 2>&1 || true
