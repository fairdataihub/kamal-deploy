# Kamal Deploy Test

This repository demonstrates deploying a Nuxt 3 application using Kamal as a deployment tool. The setup includes a local PostgreSQL database, Docker containerization, automated backups to S3/R2, and SSL certificate management.

## 🚀 Features

- **Nuxt 3** - Modern Vue.js framework
- **Kamal** - Zero-downtime deployment orchestration
- **PostgreSQL** - Relational database with Prisma ORM
- **Docker** - Containerized application deployment
- **Automated Backups** - S3/R2 cloud storage integration
- **SSL/TLS** - Automatic certificate management
- **Health Checks** - Application monitoring

## 📋 Prerequisites

Before deploying, ensure you have:

- **Ruby** (for Kamal)
- **Docker** (on your server)
- **SSH access** to your deployment server
- **S3/R2 bucket** for database backups
- **Domain name** (for SSL certificates)

## 🛠️ Local Development

### Installation

```bash
# Install dependencies
yarn install

# Generate Prisma client
yarn prisma:generate
```

### Development Server

Start the development server on `http://localhost:3000`:

```bash
yarn dev
```

### Database Setup

```bash
# Run database migrations
yarn prisma:migrate:dev

# Open Prisma Studio (database GUI)
yarn prisma:studio
```

### Building for Production

```bash
# Build the application
yarn build

# Preview production build locally
yarn preview
```

## 🚀 Deployment Setup

### 1. Install Kamal

We use Kamal for orchestrating deployments. To use Kamal you will need to install Ruby onto your machine. Although possible to install on Windows, we recommend using linux or Windows Subsystem for Linux (WSL) for the best experience.

To install Ruby:

```bash
# Ubuntu/Debian
sudo apt install ruby-full

# Fedora
sudo dnf install ruby

# macOS
brew install ruby

# Install Kamal
gem install kamal
```

### 2. Environment Configuration

Create a `.env` file in the root directory with the following variables:

```bash
# Application Configuration
KAMAL_APP_NAME=your-app-name
KAMAL_SERVER_IP=your-server-ip
KAMAL_APP_DOMAIN=your-domain.com

# Docker Registry (Docker Hub example)
KAMAL_REGISTRY_LOGIN_SERVER=docker.io
KAMAL_REGISTRY_USERNAME=your-dockerhub-username
KAMAL_REGISTRY_PASSWORD=your-dockerhub-password

# Database Configuration
DATABASE_URL=postgresql://username:password@host:5432/database
DB_HOST=your-server-ip
POSTGRES_DB=your-database-name
POSTGRES_USER=your-database-user
POSTGRES_PASSWORD=your-database-password

# S3/R2 Backup Configuration
S3_BUCKET=your-backup-bucket
S3_ENDPOINT=https://your-s3-endpoint
S3_PREFIX=backups/your-app
```
Kamal will extract these variables into `.kamal/secrets` during deployment. To view your secrets are stored, you can run:

```bash
source .env
kamal secrets print
```

### 3. SSH Setup

Ensure SSH access to your server:

```bash
# Generate SSH key if needed
ssh-keygen

# Copy public key to server
ssh-copy-id dev@your-server-ip
```

### 4. Deploy

```bash
# Initial setup and deployment
kamal setup
```

This command will:

- Install Docker and Kamal on your server
- Create the Kamal Proxy as a Docker container
- Build and deploy your application
- Set up PostgreSQL database
- Configure SSL certificates with Let's Encrypt
- Start the backup service

## 🔧 Management Commands

### Application Management

```bash
# Deploy updates
kamal deploy

# View application logs
kamal app logs

# Access application shell
kamal web-shell

# Restart application
kamal restart
```

### Database Management

```bash
# Access database shell
kamal db-shell

# Run database backup
kamal backup-db

# Restore database from backup
kamal restore-db

# Access backup container shell
kamal db-backup-shell
```

### Accessory Management

When accessories have been deployed and changes to the environment variables are made, you will need to reboot the accessory to apply the changes:

```bash
# Reboot accessory
kamal accessory reboot <accessory-name>
```

### Monitoring

```bash
# Check application status
kamal status

# View all container logs
kamal logs

# Monitor resource usage
kamal monitor
```

## 📊 Database Schema

The application uses PostgreSQL with the following schema:

```prisma
model Ping {
    id String @id
    username String
    location String
    plusOneCount Int @default(0)
    createdAt DateTime @default(now())
    updatedAt DateTime @updatedAt
}
```

## 🔄 Backup System

The application includes automated database backups:

- **Schedule**: Hourly backups (configurable)
- **Storage**: S3/R2 cloud storage
- **Encryption**: Optional GPG encryption
- **Retention**: Configurable retention policy (default: 1 day)
- **Format**: PostgreSQL custom format for efficient storage

### Backup Configuration

Backup settings can be modified in `config/deploy.yml`:

```yaml
env:
  clear:
    SCHEDULE: "@hourly" # Cron-like schedule
    BACKUP_KEEP_DAYS: "1" # Retention period
    S3_BUCKET: "your-bucket" # Storage bucket
    S3_PREFIX: "backups/app" # File prefix
```

## 🏗️ Architecture

```mermaid
flowchart LR
  Domain["Domain (your-app.com)"] --> Proxy["Kamal Proxy<br/>(SSL/TLS)"]
  subgraph Bridge["Docker Network: Kamal"]
    direction TB
    NuxtApp["Nuxt App<br/>(Port 3000)"]
    Postgres["PostgreSQL<br/>(Port 5432)"]
    Backup["Backup Service (Accessory)"]
  end
  Proxy --> NuxtApp
  NuxtApp --> Postgres
  Backup --> Postgres
  Backup --> Storage["R2/S3 Storage<br/>(backups)"]
```

## 🔒 Security

- **SSL/TLS**: Automatic certificate management via Let's Encrypt
- **Secrets**: Sensitive data stored in Kamal secrets
- **Encryption**: Optional GPG encryption for database backups
- **SSH**: Secure server access with key-based authentication

## 🐛 Troubleshooting

### Common Issues

1. **Database Connection Failed**

   ```bash
   # Check database status
   kamal accessory exec db "pg_isready"

   # View database logs
   kamal accessory logs db
   ```

2. **SSL Certificate Issues**

   ```bash
   # Check proxy status
   kamal proxy status

   # View proxy logs
   kamal proxy logs
   ```

3. **Backup Failures**

   ```bash
   # Check backup service logs
   kamal accessory logs db-backup

   # Test backup manually
   kamal backup-db
   ```

### Logs and Debugging

```bash
# View all logs
kamal logs

# Follow logs in real-time
kamal logs -f

# View specific service logs
kamal app logs
kamal accessory logs db
kamal accessory logs db-backup
```

## 📚 Additional Resources

- [Nuxt 3 Documentation](https://nuxt.com/docs/getting-started/introduction)
- [Nuxt UI Documentation](https://ui.nuxt.com)
- [Kamal Documentation](https://kamal-deploy.org)
- [Prisma Documentation](https://www.prisma.io/docs)
- [PostgreSQL Documentation](https://www.postgresql.org/docs)

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly
5. Submit a pull request

## 📄 License

This project is licensed under the MIT License.
