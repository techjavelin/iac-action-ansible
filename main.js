const core = require('@actions/core')
const exec = require('@actions/exec')
const yaml = require('yaml')
const fs = require('fs')
const os = require('os')
const path = require('path')

const { compileFunction } = require('vm')

async function main() {
    try {
        const playbook = core.getInput("playbook", { required: true })
        const requirements = core.getInput("requirements")
        const directory = core.getInput("directory")
        const key = core.getInput("key")
        const inventory = core.getInput("inventory")
        const vaultPassword = core.getInput("vault_password")
        const knownHosts = core.getInput("known_hosts")
        const options = core.getInput("options")
        const sudo    = core.getInput("sudo")
        const noColor = core.getInput("no_color")
        const checkMode = core.getInput("check_mode")
        const diff = core.getInput("diff")
        const pipenv = core.getInput("use_pipenv")

        let cmd = ["ansible-playbook", playbook]

        if (pipenv) {
            await exec.exec("pip install --user pipenv")

            let pipenv_output = "", pipenv_error = ""
            try {
                await exec.exec("pipenv install", null, {
                listeners: {
                    stdout: function(data) {
                        pipenv_output += data.toString()
                    },
                    stderr: function(data) {
                        pipenv_output += data.toString()
                    }
                }
                })

                core.setOutput("pipenv", pipenv_output)
                core.setOutput("pipenv_error", pipenv_error)
            } catch (pipenv_fail) {
                core.setOutput("pipenv_error", pipenv_error)
                core.setFailed(pipenv_fail.error)
            }
            cmd.unshift("pipenv", "run")
        }

        if (directory) {
            process.chdir(directory)
        }

        if (options) {
            cmd.push(options.replace(/\n/g, " "))
        }

        if (requirements) {
            const requirementsContent = fs.readFileSync(requirements, 'utf8')
            const requirementsObject = yaml.parse(requirementsContent)

            if (Array.isArray(requirementsObject)) {
                await exec.exec("ansible-galaxy", ["install", "-r", requirements])
            } else {
                if (requirementsObject.roles)
                    await exec.exec("ansible-galaxy", ["role", "install", "-r", requirements])
                if (requirementsObject.collections)
                    await exec.exec("ansible-galaxy", ["collection", "install", "-r", requirements])
            }
        }

        if (key) {
            const keyFile = ".ansible_key"
            fs.writeFileSync(keyFile, key + os.EOL, { mode: 0600 })
            core.saveState("keyFile", keyFile)
            cmd.push("--key-file")
            cmd.push(keyFile)
        }

        if (inventory) {
            const inventoryFile = ".ansible_inventory"
            fs.writeFileSync(inventoryFile, inventory, { mode: 0600 })
            core.saveState("inventoryFile", inventoryFile)
            cmd.push("--inventory-file")
            cmd.push(inventoryFile)
        }

        if (vaultPassword) {
            const vaultPasswordFile = ".ansible_vault_password"
            fs.writeFileSync(vaultPasswordFile, vaultPassword, { mode: 0600 })
            core.saveState("vaultPasswordFile", vaultPasswordFile)
            cmd.push("--vault-password-file")
            cmd.push(vaultPasswordFile)
        }

        if (knownHosts) {
            const knownHostsFile = ".ansible_known_hosts"
            fs.writeFileSync(knownHostsFile, knownHosts, { mode: 0600 })
            core.saveState("knownHostsFile", knownHostsFile)
            cmd.push(`--ssh-common-args="-o UserKnownHostsFile=${knownHostsFile}"`)
            process.env.ANSIBLE_HOST_KEY_CHECKING = "True"
        } else {
            process.env.ANSIBLE_HOST_KEY_CHECKING = "False"
        }

        if (sudo) {
            cmd.unshift("sudo", "-E", "env", `PATH=${process.env.PATH}`)
        }

        if (noColor) {
            process.env.ANSIBLE_NOCOLOR = "True"
        } else {
            process.env.ANSIBLE_FORCE_COLOR = "True"
        }

        if (checkMode) {
            cmd.push("--check")
        }

        if (diff) {
            cmd.push("--diff")
        }

        let output = ""
        await exec.exec(cmd.join(' '), null, {
          listeners: {
            stdout: function(data) {
              output += data.toString()
            },
            stderr: function(data) {
              output += data.toString()
            }
          }
        })
        core.setOutput("output", output)
    } catch (error) {
        core.setFailed(error.message)
    }
}

main()
