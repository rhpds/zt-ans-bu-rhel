#!/bin/bash

# Ansible for RHEL Workshop - Control Node Setup Script
# This script configures the control node for the workshop

# Disable systemd-tmpfiles-setup to avoid conflicts
systemctl stop systemd-tmpfiles-setup.service 2>/dev/null || true
systemctl disable systemd-tmpfiles-setup.service 2>/dev/null || true

# Ensure rhel user has password and sudo
echo "Configuring rhel user..."
echo "rhel:ansible123!" | chpasswd
echo "rhel ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/rhel

# Install Ansible collections available from Galaxy
echo "Installing Ansible collections..."
ansible-galaxy collection install ansible.posix --force
ansible-galaxy collection install community.general --force
# ansible.controller is bundled with the AAP image, not available on Galaxy

# Create lab directories for rhel user
echo "Creating lab directories..."
mkdir -p /home/rhel/lab_inventory
mkdir -p /home/rhel/rhel-workshop
chown -R rhel:rhel /home/rhel/lab_inventory
chown -R rhel:rhel /home/rhel/rhel-workshop

# Create inventory file for command-line exercises
echo "Creating inventory file..."
cat > /home/rhel/lab_inventory/hosts << 'EOF'
[web]
node01
node02

[db]
node03

[all:vars]
ansible_user=rhel
ansible_password=ansible123!
ansible_ssh_common_args='-o StrictHostKeyChecking=no'
EOF

chown rhel:rhel /home/rhel/lab_inventory/hosts
chmod 644 /home/rhel/lab_inventory/hosts

# Create ansible.cfg for easier command-line usage
cat > /home/rhel/lab_inventory/ansible.cfg << 'EOF'
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
EOF

chown rhel:rhel /home/rhel/lab_inventory/ansible.cfg
chmod 644 /home/rhel/lab_inventory/ansible.cfg

# Configure Automation Controller using ansible.controller collection
echo "Configuring AAP controller..."
cat > /tmp/aap-setup.yml << 'EOFAAP'
---
- name: Configure Ansible Automation Platform for RHEL Workshop
  hosts: localhost
  connection: local
  collections:
    - ansible.controller
  vars:
    controller_host: "https://localhost"
    controller_username: admin
    controller_password: ansible123!
    validate_certs: false
  tasks:

    - name: Create Workshop Organization
      ansible.controller.organization:
        name: "Workshop"
        description: "Ansible for RHEL Workshop Organization"
        state: present
        controller_host: "{{ controller_host }}"
        controller_username: "{{ controller_username }}"
        controller_password: "{{ controller_password }}"
        validate_certs: "{{ validate_certs }}"

    - name: Add Machine Credential for managed nodes
      ansible.controller.credential:
        name: 'Workshop Credential'
        organization: Workshop
        credential_type: Machine
        controller_host: "{{ controller_host }}"
        controller_username: "{{ controller_username }}"
        controller_password: "{{ controller_password }}"
        validate_certs: "{{ validate_certs }}"
        inputs:
          username: rhel
          password: ansible123!

    - name: Create Workshop Inventory
      ansible.controller.inventory:
        name: "Workshop Inventory"
        description: "RHEL nodes for workshop"
        organization: Workshop
        controller_host: "{{ controller_host }}"
        controller_username: "{{ controller_username }}"
        controller_password: "{{ controller_password }}"
        validate_certs: "{{ validate_certs }}"
        state: present

    - name: Add web group to inventory
      ansible.controller.group:
        name: web
        inventory: "Workshop Inventory"
        controller_host: "{{ controller_host }}"
        controller_username: "{{ controller_username }}"
        controller_password: "{{ controller_password }}"
        validate_certs: "{{ validate_certs }}"
        state: present

    - name: Add db group to inventory
      ansible.controller.group:
        name: db
        inventory: "Workshop Inventory"
        controller_host: "{{ controller_host }}"
        controller_username: "{{ controller_username }}"
        controller_password: "{{ controller_password }}"
        validate_certs: "{{ validate_certs }}"
        state: present

    - name: Add node01 to inventory
      ansible.controller.host:
        name: node01
        inventory: "Workshop Inventory"
        controller_host: "{{ controller_host }}"
        controller_username: "{{ controller_username }}"
        controller_password: "{{ controller_password }}"
        validate_certs: "{{ validate_certs }}"
        state: present

    - name: Add node02 to inventory
      ansible.controller.host:
        name: node02
        inventory: "Workshop Inventory"
        controller_host: "{{ controller_host }}"
        controller_username: "{{ controller_username }}"
        controller_password: "{{ controller_password }}"
        validate_certs: "{{ validate_certs }}"
        state: present

    - name: Add node01 and node02 to web group
      ansible.controller.group:
        name: web
        inventory: "Workshop Inventory"
        hosts:
          - node01
          - node02
        controller_host: "{{ controller_host }}"
        controller_username: "{{ controller_username }}"
        controller_password: "{{ controller_password }}"
        validate_certs: "{{ validate_certs }}"
        state: present

    - name: Add node03 to inventory
      ansible.controller.host:
        name: node03
        inventory: "Workshop Inventory"
        controller_host: "{{ controller_host }}"
        controller_username: "{{ controller_username }}"
        controller_password: "{{ controller_password }}"
        validate_certs: "{{ validate_certs }}"
        state: present

    - name: Add node03 to db group
      ansible.controller.group:
        name: db
        inventory: "Workshop Inventory"
        hosts:
          - node03
        controller_host: "{{ controller_host }}"
        controller_username: "{{ controller_username }}"
        controller_password: "{{ controller_password }}"
        validate_certs: "{{ validate_certs }}"
        state: present

EOFAAP

ANSIBLE_COLLECTIONS_PATH="/root/ansible-automation-platform-containerized-setup/collections/:/root/.ansible/collections/" ansible-playbook /tmp/aap-setup.yml

# Set proper ownership
chown -R rhel:rhel /home/rhel

echo "Control node setup completed successfully!"
