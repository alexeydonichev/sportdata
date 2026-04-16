module.exports = {
  apps: [{
    name: 'backend',
    script: './api-gateway',
    cwd: '/root/sportdata/api-gateway',
    env: {
      DATABASE_URL: 'postgres://sportdata_admin:Sp0rtD@ta2024SecurePass!@127.0.0.1:5432/sportdata?sslmode=disable',
      REDIS_URL: 'redis://127.0.0.1:32768',
      JWT_SECRET: 'your-secret-key-here',
      PORT: '8080'
    }
  }]
}
