# Kamal Deploy Test

This repository has been created to test using Kamal as a deployment tool for a Nuxt 3 app. This includes a local postgres database and a docker container for the server. Backups are also included.

Look at [Nuxt docs](https://nuxt.com/docs/getting-started/introduction) and [Nuxt UI docs](https://ui.nuxt.com) to learn more.

## Setup

Make sure to install the dependencies:

```bash
# npm
npm install

# pnpm
pnpm install

# yarn
yarn install

# bun
bun install
```

## Development Server

Start the development server on `http://localhost:3000`:

```bash
# npm
npm run dev

# pnpm
pnpm run dev

# yarn
yarn dev

# bun
bun run dev
```

## Production

Build the application for production:

```bash
# npm
npm run build

# pnpm
pnpm run build

# yarn
yarn build

# bun
bun run build
```

Locally preview production build:

```bash
# npm
npm run preview

# pnpm
pnpm run preview

# yarn
yarn preview

# bun
bun run preview
```


## Deployment

We use Kamal for orchestrating deployments. To use Kamal you will need to install Ruby onto your machine. Although possible to install on Windows, we recommend using linux or Windows Subsystem for Linux (WSL) for the best experience.

To install Ruby:
```bash
# Ubuntu/Debian
sudo apt install ruby-full
# Fedora
sudo dnf install ruby
# macOS
brew install ruby
# Windows (WSL)
sudo apt install ruby-full
```

To then install Kamal, run:

```bash
gem install kamal
```

Ensure you have your SSH keys set up so that Kamal can access your server. You can create a new SSH key with:

```bash
ssh-keygen
```
Then, add the public key to your server's `~/.ssh/authorized_keys` file on the remote server.
```bash
# Copy the public key to the server
ssh-copy-id user@your-server-ip
```

Now you can deploy the application, run:

```bash
kamal setup
```
This will set up the necessary tools on your server such as Docker and the Kamal Proxy and then begin the deployment process. Any other provisioning steps will need to be handled manually.

We've created Kamal aliases to make it easier to access and manage the containers. Below are some useful commands:
```bash
# Example to manually run a backup script
kamal backup-db

# To access the database shell with bash
kamal db-shell

# To access the web app's shell, you can use:
kamal web-shell
```
You can find all aliases checking the `aliases` key in the `config/deploy.yml` file.

Check out the [deployment documentation](https://nuxt.com/docs/getting-started/deployment) for more information.
